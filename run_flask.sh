#!/bin/bash
supervisord

python /app/app.py > output.txt