#!/bin/sh
IFS=':'

for p in $PATH; do
    if [ -w "$p" ]; then
        printf 'Writable     - '
    else
        printf 'Non-Writable - '
    fi

    echo "$p"
done

unset IFS