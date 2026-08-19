#!/usr/bin/env python3
import argparse
import hashlib
import shutil
from pathlib import Path

import cv2
import numpy as np
import yaml


def matrix(entry, rows, cols, name):
    values = entry.get("data", [])
    if len(values) != rows * cols:
        raise ValueError(f"{name} must contain {rows * cols} values")
    return np.asarray(values, dtype=np.float64).reshape(rows, cols)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description="Export EVK4 ROS calibration to OpenCV and Kalibr formats.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--rendering-topic", default="/dvs/dvs_rendering")
    args = parser.parse_args()

    source_path = Path(args.input)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    with source_path.open("r", encoding="utf-8") as stream:
        source = yaml.safe_load(stream)

    width = int(source["image_width"])
    height = int(source["image_height"])
    distortion_model = source.get("distortion_model", "plumb_bob")
    k = matrix(source["camera_matrix"], 3, 3, "camera_matrix")
    d = np.asarray(source["distortion_coefficients"]["data"], dtype=np.float64)
    r = matrix(source["rectification_matrix"], 3, 3, "rectification_matrix")
    p = matrix(source["projection_matrix"], 3, 4, "projection_matrix")

    ros_output = output_dir / "camera_info.yaml"
    opencv_output = output_dir / "opencv_intrinsics.yaml"
    kalibr_output = output_dir / "camchain.yaml"
    shutil.copy2(source_path, ros_output)

    storage = cv2.FileStorage(str(opencv_output), cv2.FILE_STORAGE_WRITE)
    if not storage.isOpened():
        raise RuntimeError(f"Cannot open {opencv_output} for writing")
    storage.write("image_width", width)
    storage.write("image_height", height)
    storage.write("camera_matrix", k)
    storage.write("distortion_coefficients", d.reshape(1, -1))
    storage.write("rectification_matrix", r)
    storage.write("projection_matrix", p)
    storage.release()

    if distortion_model != "plumb_bob":
        raise ValueError(f"Kalibr radtan export requires plumb_bob input, got {distortion_model}")
    if d.size < 4:
        raise ValueError("Kalibr radtan export requires at least four distortion coefficients")
    kalibr = {
        "cam0": {
            "camera_model": "pinhole",
            "intrinsics": [float(k[0, 0]), float(k[1, 1]), float(k[0, 2]), float(k[1, 2])],
            "distortion_model": "radtan",
            "distortion_coeffs": [float(value) for value in d[:4]],
            "resolution": [width, height],
            "rostopic": args.rendering_topic,
        }
    }
    with kalibr_output.open("w", encoding="utf-8") as stream:
        yaml.safe_dump(kalibr, stream, sort_keys=False)

    check = cv2.FileStorage(str(opencv_output), cv2.FILE_STORAGE_READ)
    exported_width = int(check.getNode("image_width").real())
    exported_height = int(check.getNode("image_height").real())
    exported_k = check.getNode("camera_matrix").mat()
    exported_d = check.getNode("distortion_coefficients").mat().reshape(-1)
    exported_r = check.getNode("rectification_matrix").mat()
    exported_p = check.getNode("projection_matrix").mat()
    check.release()
    if (exported_width, exported_height) != (width, height):
        raise RuntimeError("OpenCV resolution verification failed")
    if not all(
        (
            np.allclose(k, exported_k),
            np.allclose(d, exported_d),
            np.allclose(r, exported_r),
            np.allclose(p, exported_p),
        )
    ):
        raise RuntimeError("OpenCV export verification failed")

    with ros_output.open("r", encoding="utf-8") as stream:
        exported_ros = yaml.safe_load(stream)
    if exported_ros != source:
        raise RuntimeError("ROS CameraInfo export verification failed")

    with kalibr_output.open("r", encoding="utf-8") as stream:
        exported_kalibr = yaml.safe_load(stream)["cam0"]
    expected_intrinsics = [float(k[0, 0]), float(k[1, 1]), float(k[0, 2]), float(k[1, 2])]
    if (
        exported_kalibr["resolution"] != [width, height]
        or not np.allclose(exported_kalibr["intrinsics"], expected_intrinsics)
        or not np.allclose(exported_kalibr["distortion_coeffs"], d[:4])
    ):
        raise RuntimeError("Kalibr export verification failed")

    manifest = {
        "serial": args.serial,
        "source_camera_info": str(source_path),
        "source_sha256": sha256(source_path),
        "resolution": [width, height],
        "distortion_model": distortion_model,
        "kalibr_note": "The rendering topic is an accumulated event image, not a raw event topic.",
        "outputs": [str(ros_output), str(opencv_output), str(kalibr_output)],
    }
    with (output_dir / "manifest.yaml").open("w", encoding="utf-8") as stream:
        yaml.safe_dump(manifest, stream, sort_keys=False)

    print(f"ros={ros_output}")
    print(f"opencv={opencv_output}")
    print(f"kalibr={kalibr_output}")
    print("verification=passed")


if __name__ == "__main__":
    main()
