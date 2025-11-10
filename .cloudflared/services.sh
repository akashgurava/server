# Copy plist file to all existing cloudflared version folders
for version_dir in /opt/homebrew/Cellar/cloudflared/*/; do
    if [ -d "$version_dir" ]; then
        echo "Copying to: $version_dir"
        cp ${HOME}/Documents/server/.cloudflared/cloudflared.plist "$version_dir/homebrew.mxcl.cloudflared.plist"
    fi
done

cp ${HOME}/Documents/server/.cloudflared/cloudflare.yml "$HOMEBREW_PREFIX/etc/cloudflared/cloudflare.yml"
cp ${HOME}/Documents/server/.cloudflared/887b28ec-ae51-4b5f-a788-7c955f7d2eb2.json "$HOMEBREW_PREFIX/etc/cloudflared/887b28ec-ae51-4b5f-a788-7c955f7d2eb2.json"
cp ${HOME}/Documents/server/.cloudflared/cert.pem "$HOMEBREW_PREFIX/etc/cloudflared/cert.pem"

# Restart cloudflared service
brew services restart cloudflared
