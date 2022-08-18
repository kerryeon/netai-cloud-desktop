#!/bin/bash

exec yay -Sy --needed --noconfirm $(sudo cat $1 | grep -o '^[^#]*')
