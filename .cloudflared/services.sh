# Copy plist file to all existing cloudflared version folders
for version_dir in /opt/homebrew/Cellar/cloudflared/*/; do
    if [ -d "$version_dir" ]; then
        echo "Copying to: $version_dir"
        cp ${HOME}/Documents/server/.cloudflared/cloudflared.plist "$version_dir/homebrew.mxcl.cloudflared.plist"
    fi
done

# Restart cloudflared service
brew services restart cloudflared
