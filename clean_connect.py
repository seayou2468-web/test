with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

content = content.replace(
    'installation_proxy_connect(_provider, (struct InstallationProxyClientHandle **)&_afc); // Hack for test, should use afc_client_connect\n    if (err) idevice_error_free(err);',
    ''
)

with open('DeviceConnectionManager.mm', 'w') as f:
    f.write(content)
