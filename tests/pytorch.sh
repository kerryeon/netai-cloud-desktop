#!/bin/bash

docker run --rm -it --name pytorch \
    --gpus all \
    --ipc host \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    --net host \
    nvcr.io/nvidia/pytorch:21.12-py3
