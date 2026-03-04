with open('DeviceConnectionManager.mm', 'r') as f:
    content = f.read()

# Remove the incorrectly placed @end and move it to the actual end
content = content.replace('@end\n\n\n\n- (void)afcListDirectory', '\n- (void)afcListDirectory')
if not content.strip().endswith('@end'):
    content = content.strip() + '\n\n@end\n'

with open('DeviceConnectionManager.mm', 'w') as f:
    f.write(content)
