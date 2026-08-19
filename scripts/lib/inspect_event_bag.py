#!/usr/bin/env python3
import argparse

import rosbag


def to_microseconds(stamp):
    return stamp.secs * 1_000_000 + stamp.nsecs // 1_000


def main():
    parser = argparse.ArgumentParser(description="Count events and timestamps in a ROS1 event bag.")
    parser.add_argument("bag")
    parser.add_argument("--topic", default="/dvs/events")
    args = parser.parse_args()

    message_count = 0
    event_count = 0
    first_event_us = None
    last_event_us = None
    first_bag_time = None
    last_bag_time = None
    datatype = ""
    width = 0
    height = 0

    with rosbag.Bag(args.bag, "r") as bag:
        topic_info = bag.get_type_and_topic_info().topics.get(args.topic)
        if topic_info is not None:
            datatype = topic_info.msg_type
        for _, message, bag_time in bag.read_messages(topics=[args.topic]):
            message_count += 1
            first_bag_time = bag_time.to_sec() if first_bag_time is None else first_bag_time
            last_bag_time = bag_time.to_sec()
            events = getattr(message, "events", [])
            width = width or getattr(message, "width", 0)
            height = height or getattr(message, "height", 0)
            event_count += len(events)
            if events:
                current_first = to_microseconds(events[0].ts)
                current_last = to_microseconds(events[-1].ts)
                first_event_us = current_first if first_event_us is None else min(first_event_us, current_first)
                last_event_us = current_last if last_event_us is None else max(last_event_us, current_last)

    print(f"topic={args.topic}")
    print(f"datatype={datatype}")
    print(f"message_count={message_count}")
    print(f"event_count={event_count}")
    print(f"width={width}")
    print(f"height={height}")
    print(f"first_event_us={first_event_us or 0}")
    print(f"last_event_us={last_event_us or 0}")
    event_duration_s = (
        (last_event_us - first_event_us) / 1_000_000
        if first_event_us is not None and last_event_us is not None
        else 0
    )
    print(f"event_duration_s={event_duration_s}")
    print(f"bag_duration_s={(last_bag_time - first_bag_time) if first_bag_time is not None else 0}")


if __name__ == "__main__":
    main()
