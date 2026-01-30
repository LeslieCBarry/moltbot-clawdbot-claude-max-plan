#!/bin/bash
# Opens SSH tunnel to your Moltbot EC2 and launches dashboard in browser
# Usage: ./open-dashboard.sh

EC2_IP="${EC2_IP:-YOUR_EC2_IP_HERE}"
KEY="${SSH_KEY:-$HOME/.ssh/your-key.pem}"
PORT=18789

if [ "$EC2_IP" = "YOUR_EC2_IP_HERE" ]; then
    echo "Error: Set EC2_IP first."
    echo "  export EC2_IP=1.2.3.4"
    echo "  export SSH_KEY=~/.ssh/your-key.pem"
    echo "  ./open-dashboard.sh"
    exit 1
fi

lsof -ti tcp:$PORT | xargs kill 2>/dev/null
ssh -f -N -L $PORT:127.0.0.1:$PORT -i "$KEY" ubuntu@$EC2_IP
open "http://127.0.0.1:$PORT/" 2>/dev/null || xdg-open "http://127.0.0.1:$PORT/" 2>/dev/null || echo "Open http://127.0.0.1:$PORT/ in your browser"

echo "Dashboard tunnel running. To stop: lsof -ti tcp:$PORT | xargs kill"
