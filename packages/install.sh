#!/bin/bash

exec yay -S --needed --noconfirm $(sudo cat $1 | grep -o '^[^#]*')
