#!/usr/bin/env python3
import argparse
import heapq
import os
import tempfile

import rosbag


def message_stamp(message, bag_stamp):
    events = getattr(message, "events", None)
    if events:
        return events[0].ts
    header = getattr(message, "header", None)
    if header is not None and header.stamp.to_nsec() > 0:
        return header.stamp
    return bag_stamp


def ordered_topic_messages(path, selected_topic):
    bag = rosbag.Bag(path, "r")
    previous_ns = None
    try:
        for topic, message, bag_stamp in bag.read_messages(topics=[selected_topic]):
            stamp = message_stamp(message, bag_stamp)
            stamp_ns = stamp.to_nsec()
            if previous_ns is not None and stamp_ns < previous_ns:
                raise RuntimeError(
                    f"{path}:{selected_topic} is not monotonic by event/header time: "
                    f"{stamp_ns} < {previous_ns}"
                )
            previous_ns = stamp_ns
            yield topic, message, stamp
    finally:
        bag.close()


def bag_topics(path):
    with rosbag.Bag(path, "r") as bag:
        return sorted(bag.get_type_and_topic_info().topics)


def main():
    parser = argparse.ArgumentParser(
        description="Merge per-camera ROS bags by event/header timestamp."
    )
    parser.add_argument("--output", required=True)
    parser.add_argument("inputs", nargs="+")
    args = parser.parse_args()

    iterators = [
        iter(ordered_topic_messages(path, topic))
        for path in args.inputs
        for topic in bag_topics(path)
    ]
    heap = []
    counter = 0
    for source, iterator in enumerate(iterators):
        try:
            topic, message, stamp = next(iterator)
        except StopIteration:
            continue
        heapq.heappush(
            heap, (stamp.to_nsec(), counter, source, topic, message, stamp)
        )
        counter += 1

    output_dir = os.path.dirname(os.path.abspath(args.output))
    os.makedirs(output_dir, exist_ok=True)
    temporary = tempfile.NamedTemporaryFile(
        prefix=".merge_event_bags_", suffix=".bag", dir=output_dir, delete=False
    )
    temporary_path = temporary.name
    temporary.close()
    try:
        last_ns = None
        with rosbag.Bag(temporary_path, "w") as output:
            while heap:
                stamp_ns, _, source, topic, message, stamp = heapq.heappop(heap)
                if last_ns is not None and stamp_ns < last_ns:
                    raise RuntimeError("Merged event/header timestamps are not monotonic")
                output.write(topic, message, stamp)
                last_ns = stamp_ns
                try:
                    topic, message, stamp = next(iterators[source])
                except StopIteration:
                    continue
                heapq.heappush(
                    heap,
                    (stamp.to_nsec(), counter, source, topic, message, stamp),
                )
                counter += 1
        os.replace(temporary_path, args.output)
    finally:
        for iterator in iterators:
            iterator.close()
        if os.path.exists(temporary_path):
            os.unlink(temporary_path)


if __name__ == "__main__":
    main()
