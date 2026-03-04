with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# Fix the hacky connect logic
content = content.replace(
    'err = installation_proxy_connect(_provider, &_instproxy);\n    afc_client_connect(_provider, &_afc);',
    'err = installation_proxy_connect(_provider, &_instproxy);\n    if (err) idevice_error_free(err);\n    err = afc_client_connect(_provider, &_afc);\n    if (err) idevice_error_free(err);'
)

with open('DeviceConnectionManager.mm', 'w') as f:
    f.write(content)
