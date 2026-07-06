#!/bin/bash

# Speed Insights script to be inserted
SPEED_INSIGHTS='    \
    <!-- Vercel Speed Insights -->\
    <script>\
      window.si = window.si || function () { (window.siq = window.siq || []).push(arguments); };\
    </script>\
    <script defer src="/_vercel/speed-insights/script.js"></script>'

# Process each HTML file except index.html (already done)
for file in *.html; do
    if [ "$file" != "index.html" ] && [ ! -f "${file}.bak" ]; then
        # Check if Speed Insights is already present
        if ! grep -q "vercel/speed-insights" "$file"; then
            echo "Adding Speed Insights to $file"
            # Use sed to insert before </head>
            sed -i.bak "s|</head>|${SPEED_INSIGHTS}\n</head>|" "$file"
        else
            echo "Speed Insights already in $file"
        fi
    fi
done

# Clean up backup files
rm -f *.html.bak

echo "Done adding Speed Insights to all HTML files"
