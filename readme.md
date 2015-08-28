## Expose 2.0

A simple static site generator for photoessays

### Intro

If you're into photography, you probably have folders of images and videos like this:

![a bunch of images](http://jack.works/exposeimages/folder.jpg)

Expose is a Bash script that turns those folders into photoessays similar to [jack.ventures](http://jack.ventures) or [jack.works](http://jack.works) (my personal blogs)

If you're not a fan of that look, a [Medium-style theme](http://jack.ventures/sample/) is also included

tested on Windows/Cygwin, OSX, and should be fine on Linux

### Installation

The only dependency is Imagemagick. For videos FFmpeg is also required.

download the repo and alias the script
	
	alias expose=/script/location/expose.sh

for permanent use add this line to your ~/.profiles, ~/.bashrc etc depending on system

### Simple usage

	cd ~/folderofimages
	expose

The script operates on your current working directory, and outputs a _sites directory.
Configuration and settings can be edited in the expose.sh file itself

### Adding text

The text associated with each image is read from any text file with the same filename as the image, eg:

![images and text files](http://jack.works/exposeimages/imagetext.jpg)

### Sorting

Images are sorted by alphabetical order. To arbitrarily order images, add a numerical prefix

### Organization

You can put images in folders to organize them. The folders can be nested any number of times, and are also sorted alphabetically. Keep in mind the url of each gallery corresponds to the relative path of the folder.

To arbitrarily order folders, add a numerical prefix to the folder name. Any numerical prefixes are stripped from the url.

![folders](http://jack.works/exposeimages/folders.jpg)

### Text metadata

YAML in the text file is read and made available to the template. The variables depend on the template used.