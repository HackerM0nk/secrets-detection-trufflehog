import os
import sys

# get directory (of current file)
dir_path = os.path.dirname(os.path.realpath(__file__))

# get base filename (without extension) (of current file)
basename = os.path.basename(os.path.realpath(__file__))

# get relative path from arg
mypath = sys.argv[1]

# iterate dirs and files
for f in os.listdir(mypath):
    path = os.path.join(mypath, f)
    # print if file
    if os.path.isfile(path):
        print os.path.join(dir_path, path)

# iterate and rename files
dir = mypath
for f in os.listdir(dir):
    basename, ext = os.path.splitext(f)
    if ext == '.jpg':
        new_name = basename.split('_')[0].lower() + ext
        os.rename(os.path.join(dir, f), os.path.join(dir, new_name))
