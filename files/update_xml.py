#!/usr/bin/env python
from xml.etree import ElementTree as et
from xml.etree.ElementTree import SubElement as SubE
import re
import os.path
import sys

if len(sys.argv) != 5:
    print('Exactly 4 arguments required (file, path, value, type)')
    sys.exit(1)

filename, path, value, datatype = sys.argv[1:]

print('Path: **{0}**, value: **{1}**'.format(path, value))

filename = os.path.join('/storage/.kodi', filename)

tree = et.parse(filename)
root = tree.getroot()

# do we need to create this node/tree?
match = root.find(path)

# ok, yes we do
if not match:
    path_components = re.findall(r'[a-z0-9]+(?:\[@[^]]+\])?', path)
    mount_element = root
    for node in path_components:
        match = mount_element.find(node)
        if match is None:
            break
        else:
            print('found {0}'.format(node))
            mount_element = match
            path_components.pop(0)
    parent = mount_element
    for node in path_components:
        node_name = re.match(r'[^[]+', node).group(0)
        match = re.search(r'@([^=]+)="?([^"]]+)"?]', node)
        match = re.search(r'\[@([^=]+)="?([^]"]+)"?', node)
        if match:
            attribute_name, attribute_value = match.group(1), match.group(2)
            print(attribute_name, attribute_value)
            parent = SubE(parent, node_name, {match.group(1): match.group(2)})
        else:
            parent = SubE(parent, node_name)
    match = root.find(path)

# setting value
match.text = str(value)
match.attrib.update({'type': datatype})
if 'default' in match.attrib:
    match.attrib.pop('default')

# et.dump(root)
# write the changes back
tree.write(filename)
