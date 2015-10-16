#!/usr/bin/env bash

# configuration

site_title=${site_title:-"My Awesome Photos"}

theme_dir=${theme_dir:-"theme1"}

# widths to scale images to (heights are calculated from source images)
# you might want to change this for example, if your images aren't full screen on the browser side
resolution=(3840 2560 1920 1280 1024 640)

# jpeg compression quality for static photos
jpeg_quality=${jpeg_quality:-92}

# formats to encode to, list in order of preference. Available formats are vp9, vp8, h264, ogv
video_formats=(h264 vp8)

# video quality - target bitrates in MBit/s matched to each resolution
# feel free to ignore this if you don't have any videos.
# the defaults are about 3x vimeo/youtube bitrates to match photographic quality. Personal tolerance to compression artefacts vary, so adjust to taste.

bitrate=(40 24 12 7 4 2)

bitrate_maxratio=2 # a multiple of target bitrate to get max bitrate for VBR encoding. must be > 1. Higher ratio gives better quality on scenes with lots of movement. Ratio=1 reduces to CBR encoding

disable_audio=${disable_audio:-true}

# extract a representative palette for each photo/video and use those colors for background/text/accent etc
extract_colors=${extract_colors:-true}

backgroundcolor=${backgroundcolor:-"#000000"} # slide background, visible only before image has loaded
textcolor=${textcolor:-"#ffffff"} # default text color

# palette of 7 colors, background to foreground, to be used if color extraction is disabled
default_palette=("#000000" "#222222" "#444444" "#666666" "#999999" "#cccccc" "#ffffff")

override_textcolor=${override_textcolor:-true} # use given text color instead of extracted palette on body text.

# display a toggle button to show/hide the text
text_toggle=${text_toggle:-true}

social_button=${social_button:-true}

# option to put the full image/video in a zip file with a license readme.txt
download_button=${download_button:-false}
download_readme=${dowmload_readme:-"All rights reserved"}

# disqus forum name. Leave blank to disable comments
disqus_shortname=${disqus_shortname:-""}

# arbitrary list of extensions we'll assume are video files.
video_extensions=(3g2 3gp 3gp2 asf avi dvr-ms exr ffindex ffpreset flv gxf h261 h263 h264 ifv m2t m2ts mts m4v mkv mod mov mp4 mpg mxf tod vob webm wmv y4m)

sequence_keyword="imagesequence" # if a directory name contains this keyword, treat it as an image sequence and compile it into a video
sequence_framerate=24 # sequence framerate

# specific codec options here
h264_encodespeed=${h264_encodespeed:-"veryslow"} # h264 encode speed, slower produces better compression results. Options are ultrafast,superfast, veryfast, faster, fast, medium, slow, slower, veryslow
vp9_encodespeed=${vp9_encodespeed:-1} # VP9 encode speed, 0 is best and slowest, 4 for fastest. VP9 is very slow to encode in general. Note that 0 is dramatically slower than 1 with marginal quality improvement

ffmpeg_threads=${ffmpeg_threads:-0} # the -threads option for ffmpeg encode (0=auto). This could be useful, for example if you need to throttle CPU load on a server that's doing other things.

# script starts here

command -v convert >/dev/null 2>&1 || { echo "ImageMagick is a required dependency, aborting..." >&2; exit 1; }
command -v identify >/dev/null 2>&1 || { echo "ImageMagick is a required dependency, aborting..." >&2; exit 1; }

# file extensions for each video format
video_format_extensions=("h264" "mp4" "h265" "mp4" "vp9" "webm" "vp8" "webm" "ogv" "ogv")

topdir=$(pwd)
scriptdir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

draft=false
# the -d flag has been set
while getopts ":d" opt; do
  case "$opt" in
    d)
		echo "Draft mode On"
		draft=true
		# for a quick draft, use lowest resolution, fastest encode rates etc.
		resolution=(1024)
		bitrate=(4)
		video_formats=(h264)
		download_button=false
		;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      ;;
  esac
done

video_enabled=false
if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1
then
	video_enabled=true
fi

# directory structure will form nav structure
paths=() # relevant non-empty dirs in $topdir
nav_name=() # a front-end friendly label for each item in paths[], with numeric prefixes stripped
nav_depth=() # depth of each navigation item
nav_type=() # 0 = structure, 1 = leaf. Where a leaf directory is a gallery of images
nav_url=() # a browser-friendly url for each path, relative to _site
nav_count=() # the number of images in each gallery, or -1 if not a leaf

metadata_file="metadata.txt" # search for this file in each gallery directory for gallery-wide metadata

gallery_files=() # a flat list of all gallery images and videos
gallery_nav=() # index of nav item the gallery image belongs to
gallery_url=() # url-friendly name of each image
gallery_type=() # 0 = image, 1 = video, 2 = image sequence
gallery_maxwidth=() # maximum image size available
gallery_maxheight=() # maximum height
gallery_colors=() # extracted color palette for each image

gallery_image_options=() # image commands extracted from post metadata
gallery_video_options=() # video commands extracted from post metadata
gallery_video_filters=() # filter commands added to ffmpeg calls

# scan working directory to populate $nav variables
root_depth=$(echo "$topdir" | awk -F"/" "{ print NF }")

# if on cygwin, transforms given param to windows style path
winpath () {
	if command -v cygpath >/dev/null 2>&1
	then
		cygpath -m "$1"
	else
		echo "$1"
	fi
}

# $1: template, $2: {{ variable name }}, $3: replacement string
template () {
	key=$(echo "$2" | tr -d '[:space:]')
	
	value=""
	while read -r line
	do
		value+=$(echo "$line" | sed -e 's/\\/\\\\/g' -e 's/\//\\\//g' -e 's/&/\\\&/g') # escape slashes
	done <<< "$3"
	
	while read -r line
	do
		echo "$line" | sed "s/{{$key}}/${value}/g; s/{{$key:[^}]*}}/${value}/g"
	done <<< "$1"
}

scratchdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'exposetempdir')
scratchdir=$(winpath "$scratchdir")

if [ -z "$scratchdir" ]
then
	echo "Could not create scratch directory" >&2; exit 1;
fi

chmod -R 740 "$scratchdir"

output_url=""

cleanup() {
	# remove any ffmpeg log/temp files
	rm -f ffmpeg*.log
	rm -f ffmpeg*.mbtree
	rm -f ffmpeg*.temp
	
	if [ -d "$scratchdir" ]
    then
        rm -r "$scratchdir"
    fi
	
	if [ -e "$output_url" ]
	then
		rm -f "$output_url"
	fi
	
	exit
}

trap cleanup EXIT INT TERM

printf "Scanning directories"

while read node
do
	printf "."
	
	if [ "$node" = "$topdir/_site" ]
	then
		continue
	fi
	
	node_depth=$(echo "$node" | awk -F"/" "{ print NF-$root_depth }")
	
	# ignore empty directories
	if find "$node" -maxdepth 0 -empty | read v
	then
		continue
	fi
	
	node_name=$(basename "$node" | sed -e 's/^[0-9]*//' | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')
	if [ -z "$node_name" ]
	then
		node_name=$(basename "$node")
	fi
		
	dircount=$(find "$node" -maxdepth 1 -type d ! -path "$node" ! -path "$node*/_*" | wc -l)
	dircount_sequence=$(find "$node" -maxdepth 1 -type d ! -path "$node" ! -path "$node/_site" ! -path "$node/*$sequence_keyword*" | wc -l)
	
	if [ "$dircount" -gt 0 ]
	then
		if [ -z "$sequence_keyword" ] || [ "$dircount_sequence" -gt 0 ]
		then
			node_type=0
		else
			node_type=1
		fi
	else
		if [ ! -z "$sequence_keyword" ] && [ $(echo "$node_name" | grep "$sequence_keyword" | wc -l) -gt 0 ]
		then
			continue
		else
			node_type=1
		fi
	fi
	
	paths+=("$node")
	nav_name+=("$node_name")
	nav_depth+=("$node_depth")
	nav_type+=("$node_type")
done < <(find "$topdir" -type d ! -path "$topdir*/_*" | sort)

# re-create directory structure
mkdir -p "$topdir/_site"

dir_stack=()
url_rel=""
nav_url+=(".") # first item in paths will always be $topdir

printf "\nPopulating nav"

for i in "${!paths[@]}"
do
	printf "."
	
	if [ "$i" = 0 ]
	then
		continue
	fi
	
	path="${paths[i]}"
	if [ "$i" -gt 1 ]
	then	
		if [ "${nav_depth[i]}" -gt "${nav_depth[i-1]}" ]
		then
			# push onto stack when we go down a level
			dir_stack+=("$url_rel")
		elif [ "${nav_depth[i]}" -lt "${nav_depth[i-1]}" ]
		then
			# pop stack with respect to current level
			diff="${nav_depth[i-1]}"
			while [ "$diff" -gt "${nav_depth[i]}" ]
			do
				unset dir_stack[${#dir_stack[@]}-1]
				((diff--))
			done
		fi
	fi
	
	url_rel=$(echo "${nav_name[$i]}" | sed 's/[^ a-zA-Z0-9]//g;s/ /-/g' | tr '[:upper:]' '[:lower:]')
	
	url=""
	for u in "${dir_stack[@]}"
	do
		url+="$u/"
	done
	
	url+="$url_rel"
	mkdir -p "$topdir/_site/$url"
	
	nav_url+=("$url")
done

printf "\nReading files"

# read in each file to populate $gallery variables
for i in "${!paths[@]}"
do
	nav_count[i]=-1
	if [ "${nav_type[i]}" -lt 1 ]
	then
		continue
	fi
	
	dir="${paths[i]}"
	name="${nav_name[i]}"
	url="${nav_url[i]}"
	
	mkdir -p "$topdir"/_site/"$url"

	index=0
	
	# loop over found files
	while read file
	do
		
		printf "."
		
		filename=$(basename "$file")
		filedir=$(dirname "$file")
		filepath=$(winpath "$file")
		
		trimmed=$(echo "${filename%.*}" | sed -e 's/^[[:space:]0-9]*//;s/[[:space:]]*$//')
		
		if [ -z "$trimmed" ]
		then
			trimmed=$(echo "${filename%.*}")
		fi
		
		image_url=$(echo "$trimmed" | sed 's/[^ a-zA-Z0-9]//g;s/ /-/g' | tr '[:upper:]' '[:lower:]')
		
		if [ -d "$file" ] && [ $(echo "$filename" | grep "$sequence_keyword" | wc -l) -gt 0 ]
		then
			format="sequence"
			image=$(find "$file" -maxdepth 1 ! -path "$file" | sort | head -n 1)
		else
			format=$(identify -format "%m" "$file" 2>/dev/null | tr '[:upper:]' '[:lower:]')
		fi
		
		if [ "$format" != "jpeg" ] && [ "$format" != "png" ] && [ "$format" != "gif" ] && [ "$format" != "sequence" ]
		then
		
			extension=$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')
			
			# identify command may not be reliable, trust that extensions aren't lying if available
			if [ "$extension" = "jpg" ] || [ "$extension" = "png" ] || [ "$extension" = "gif" ]
			then
				format="$extension"
			else
				# could be a video file
				if [ "$video_enabled" = false ]
				then
					continue
				fi
				
				# first check file headers for video, then use ffmpeg directly

				found=false
				for e in "${video_extensions[@]}"
				do
					if [ "$e" = "$extension" ]
					then
						found=true
						break
					fi
				done
				
				if [ "$found" = false ]
				then
					file -ib "$filename" | grep video >/dev/null || continue # not image or video or sequence, ignore
				fi
				
				format="video"
			fi
		fi
				
		if [ "$format" = "video" ]
		then
			# generate image from video file first
			temppath=$(winpath "$scratchdir/temp.jpg")
			
			ffmpeg -loglevel error -y -i "$filepath" -vf "select=gte(n\,1)" -vframes 1 -qscale:v 2 "$temppath" < /dev/null
			image="$scratchdir/temp.jpg"
						
		elif [ "$format" != "sequence" ]
		then
			image="$file"
		fi
				
		if [ "$extract_colors" = true ]
		then
			palette=$(convert "$image" -resize 200x200 -depth 4 +dither -colors 7 -unique-colors txt:- | tail -n +2 | awk 'BEGIN{RS=" "} /#/ {print}' 2>&1)
		else
			palette=""
			for p in "${default_palette[@]}"
			do
				palette+="$p"$'\n'
			done
		fi
		width=$(identify -format "%w" "$image")
		height=$(identify -format "%h" "$image")

		maxwidth=0
		maxheight=0
		count=0
		
		for res in "${resolution[@]}"
		do
			((count++))
			# store max values for later use
			if [ "$width" -ge "$res" ] && [ "$res" -gt "$maxwidth" ]
			then
				maxwidth="$res"
				maxheight=$((res*height/width))
			elif [ "$maxwidth" -eq 0 ] && [ "$count" = "${#resolution[@]}" ]
			then
				maxwidth="$res"
				maxheight=$((res*height/width))
			fi
		done
				
		((index++))
		
		# store file and type for later use
		gallery_files+=("$file")
		gallery_nav+=("$i")
		gallery_url+=("$image_url")
		
		if [ "$format" = "sequence" ]
		then
			gallery_type+=(2)
		elif [ "$format" = "video" ]
		then
			gallery_type+=(1)
		else
			gallery_type+=(0)
		fi
		gallery_maxwidth+=("$maxwidth")
		gallery_maxheight+=("$maxheight")
		gallery_colors+=("$palette")
	done < <(find "$dir" -maxdepth 1 ! -path "$dir" ! -path "$dir*/_*" | sort)
	
	nav_count[i]="$index"
done

# build html file for each gallery
template=$(cat "$scriptdir/$theme_dir/template.html")
post_template=$(cat "$scriptdir/$theme_dir/post-template.html")

gallery_index=0
firsthtml=""
firstpath=""

printf "\nBuilding HTML"

for i in "${!paths[@]}"
do
	if [ "${nav_type[i]}" -lt 1 ]
	then
		continue
	fi
	
	html="$template"
	
	gallery_metadata=""
	if [ -e "${paths[i]}/$metadata_file" ]
	then
		gallery_metadata=$(cat "${paths[i]}/$metadata_file")
	fi
	
	j=0
	while [ "$j" -lt "${nav_count[i]}" ]
	do
	
		printf "." # show progress
		
		k=$((j+1))
		file_path="${gallery_files[gallery_index]}"
		file_type="${gallery_type[gallery_index]}"
		
		# try to find a text file with the same name
		filename=$(basename "$file_path")
		filename="${filename%.*}"

		filedir=$(dirname "$file_path")
		
		type="image"
		if [ "${gallery_type[gallery_index]}" -gt 0 ]
		then
			type="video"
		fi
		
		textfile=$(find "$filedir/$filename".txt "$filedir/$filename".md ! -path "$file_path" -print -quit 2>/dev/null)
		
		metadata=""
		content=""
		if file "$textfile" | grep -q text
		then
			# if there are two lines "---", the lines preceding the second "---" are assumed to be metadata
			text=$(cat "$textfile" | tr -d $'\r')
			text=${text%$'\n'}
			metaline=$(echo "$text" | grep -n -m 2 -- "^---$" | tail -1 | cut -d ':' -f1)
						
			if [ "$metaline" ]
			then
				sumlines=$(echo "$text" | wc -l)
				taillines=$((sumlines-metaline))
				
				metadata=$(head -n "$metaline" "$textfile")
				content=$(tail -n "$taillines" "$textfile")
			else
				metadata=""
				content=$(echo "$text")
			fi
		fi
		
		metadata+=$'\n'
		metadata+="$gallery_metadata"
		metadata+=$'\n'
		z=1
		while read line
		do
			# add generated palette to metadata
			metadata="$metadata""color$z:$line"$'\n'
			((z++))
		done < <(echo "${gallery_colors[gallery_index]}")
		
		backgroundcolor=$(echo "${gallery_colors[gallery_index]}" | sed -n 2p)
		if [ "$override_textcolor" = false ]
		then
			textcolor=$(echo "${gallery_colors[gallery_index]}" | tail -1)
		fi
		
		# if perl available, pass content through markdown parser
		if command -v perl >/dev/null 2>&1
		then
			content=$(perl "$scriptdir/Markdown_1.0.1/Markdown.pl" --html4tags <(echo "$content"))
		fi
		
		# write to post template
		post=$(template "$post_template" index "$k")
		
		post=$(template "$post" post "$content")
		
		while read line
		do
			key=$(echo "$line" | cut -d ':' -f1 | tr -d $'\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
			value=$(echo "$line" | cut -d ':' -f2- | tr -d $'\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
			colon=$(echo "$line" | grep ':')

			if [ "$key" ] && [ "$value" ] && [ "$colon" ]
			then
				post=$(template "$post" "$key" "$value")
				
				if [ "$key" = "image-options" ]
				then
					gallery_image_options[gallery_index]="$value"
				fi
				
				if [ "$key" = "video-options" ]
				then
					gallery_video_options[gallery_index]="$value"
				fi
				
				if [ "$key" = "video-filters" ]
				then
					gallery_video_filters[gallery_index]="$value"
				fi
			fi
		done < <(echo "$metadata")
		
		# set image parameters
		post=$(template "$post" imageurl "${gallery_url[gallery_index]}")
		post=$(template "$post" imagewidth "${gallery_maxwidth[gallery_index]}")
		
		post=$(template "$post" imageheight "${gallery_maxheight[gallery_index]}")
		
		# set colors
		post=$(template "$post" textcolor "$textcolor")
		post=$(template "$post" backgroundcolor "$backgroundcolor")
		
		post=$(template "$post" type "$type")

		html=$(template "$html" content "$post {{content}}")
		html=$(echo "$html" | sed -e $'s/{{content}}/\\\n{{content}}/g' ) # add a newline outside templating function to break up long lines
		
		((gallery_index++))
		((j++))
	done
	
	#write html file
	html=$(template "$html" sitetitle "$site_title")
	html=$(template "$html" gallerytitle "${nav_name[i]}")
	
	html=$(template "$html" disqus_shortname "$disqus_shortname")
	
	resolutionstring=$(printf "%s " "${resolution[@]}")
	html=$(template "$html" resolution "$resolutionstring")
	
	formatstring=$(printf "%s " "${video_formats[@]}")
	html=$(template "$html" videoformats "$formatstring")
	
	display=$([ "$text_toggle" = true ] && echo "block" || echo "none")
	html=$(template "$html" text_toggle "$display")
	
	display=$([ "$social_button" = true ] && echo "block" || echo "none")
	html=$(template "$html" social_button "$display")
	
	display=$([ "$download_button" = true ] && echo "block" || echo "none")
	html=$(template "$html" download_button "$display")
	
	# build main navigation
	navigation=""
	
	# write html menu via depth first search
	depth=1
	prevdepth=0
	
	remaining="${#paths[@]}"
	parent=-1
	
	while [ "$remaining" -gt 1 ]
	do
		for j in "${!paths[@]}"
		do
			if [ "$depth" -gt 1 ] && [ "${nav_depth[j]}" = "$prevdepth" ]
			then
				parent="$j"
			fi
			
			if [ "$i" = "$j" ]
			then
				active="active"
			else
				active=""
			fi
			
			if [ "$parent" -lt 0 ] && [ "${nav_depth[j]}" = 1 ]
			then
				if [ "${nav_type[j]}" = 0 ]
				then
					navigation+="<li><span class=\"label\">${nav_name[j]}</span><ul>{{marker$j}}</ul></li>"
				else
					gindex=0
					for k in "${!gallery_nav[@]}"
					do
						if [ "${gallery_nav[k]}" = "$j" ]
						then
							gindex="$k"
							break
						fi
					done
					navigation+="<li class=\"gallery $active\"  data-image=\"${gallery_url[gindex]}\"><a href=\"{{basepath}}${nav_url[j]}\"><span>${nav_name[j]}</span></a><ul>{{marker$j}}</ul></li>"
				fi
				((remaining--))
			elif [ "${nav_depth[j]}" = "$depth" ]
			then
				if [ "${nav_type[j]}" = 0 ]
				then
					substring="<li><span class=\"label\">${nav_name[j]}</span><ul>{{marker$j}}</ul></li>{{marker$parent}}"
				else
					gindex=0
					for k in "${!gallery_nav[@]}"
					do
						if [ "${gallery_nav[k]}" = "$j" ]
						then
							gindex="$k"
							break
						fi
					done
					substring="<li class=\"gallery $active\" data-image=\"${gallery_url[gindex]}\"><a href=\"{{basepath}}${nav_url[j]}\"><span>${nav_name[j]}</span></a><ul>{{marker$j}}</ul></li>{{marker$parent}}"
				fi
				navigation=$(template "$navigation" "marker$parent" "$substring")
				((remaining--))
			fi
		done
		((prevdepth++))
		((depth++))
	done
	
	html=$(template "$html" navigation "$navigation")
	
	if [ -z "$firsthtml" ]
	then
		firsthtml="$html"
		firstpath="${nav_url[i]}"
	fi
	
	if [ "${nav_depth[i]}" = 0 ]
	then
		basepath="./"
	else
		basepath=$(yes "../" | head -n ${nav_depth[i]} | tr -d '\n')
	fi
	
	html=$(template "$html" basepath "$basepath")
	html=$(template "$html" disqus_identifier "${nav_url[i]}")
	
	# set default values for {{XXX:default}} strings
	html=$(echo "$html" | sed "s/{{[^{}]*:\([^}]*\)}}/\1/g")
	
	# remove references to any unused {{xxx}} template variables and empty <ul>s from navigation
	html=$(echo "$html" | sed "s/{{[^}]*}}//g; s/<ul><\/ul>//g")
	
	echo "$html" > "$topdir/_site/${nav_url[i]}"/index.html
	
done

# write top level index.html

basepath="./"
firsthtml=$(template "$firsthtml" basepath "$basepath")
firsthtml=$(template "$firsthtml" disqus_identifier "$firstpath")
firsthtml=$(template "$firsthtml" resourcepath "$firstpath/")
firsthtml=$(echo "$firsthtml" | sed "s/{{[^{}]*:\([^}]*\)}}/\1/g")
firsthtml=$(echo "$firsthtml" | sed "s/{{[^}]*}}//g; s/<ul><\/ul>//g")
echo "$firsthtml" > "$topdir/_site"/index.html

printf "\nStarting encode\n"

# resize images, encode videos, compile image sequences
for i in "${!gallery_files[@]}"
do
	echo -e "${gallery_url[i]}"
	
	navindex="${gallery_nav[i]}"
	url="${nav_url[navindex]}/${gallery_url[i]}"
	
	mkdir -p "$topdir/_site/$url"
	
	if [ "${gallery_type[i]}" = 0 ]
	then		
		image="${gallery_files[i]}"
	else
		filepath="${gallery_files[i]}"
		
		if [ "${gallery_type[i]}" = 2 ]
		then
			# compile images into a high-quality video, then treat as normal video
			seqfinished=true
			for j in "${!resolution[@]}"
			do
				res="${resolution[$j]}"
				
				for vformat in "${video_formats[@]}"
				do				
					videofile="$res-$vformat."
					
					for k in "${!video_format_extensions[@]}"
					do
						if [ "${video_format_extensions[k]}" = "$vformat" ]
						then
							videofile+="${video_format_extensions[k+1]}"
							break
						fi
					done
					
					if [ ! -s "$topdir/_site/$url/$videofile" ]
					then
						seqfinished=false
						break
					fi
				done
			done
			
			if [ "$seqfinished" = true ]
			then
				continue
			fi
			
			echo "Compiling sequence images"
			
			# ffmpeg's image sequence feature is oddly limited and can't accept arbitrarily named files, copy to scratch dir as sequentially named files
			j=0
			while read seqfile
			do
				tempname=$(printf "%04d" "$j")
				cp "$seqfile" "$scratchdir/$tempname"
				((j++))
			done < <(find "$filepath" -maxdepth 1 ! -path "$filepath" | sort)
			sequencevideo="$scratchdir/sequencevideo.mp4"
			
			maxres=$(printf '%s\n' "${resolution[@]}" | sort -n | tail -n 1)
			
			ffmpeg -loglevel error -f image2 -y -i "$scratchdir/%04d" -c:v libx264 -threads "$ffmpeg_threads" -vf scale="$maxres:trunc(ow/a/2)*2" -profile:v high -pix_fmt yuv420p -preset "$h264_encodespeed" -crf 15 -r "$sequence_framerate" -f mp4 "$sequencevideo"
			
			filepath="$sequencevideo"
		fi
		
		filepath=$(winpath "$filepath")
		
		# use ffmpeg to encode h264 videos for each resolution
		dimensions=$(ffprobe -v error -of flat=s=_ -select_streams v:0 -show_entries stream=width,height "$filepath")
		width=$(echo "$dimensions" | sed -n 1p | cut -d '=' -f2 )
		height=$(echo "$dimensions" | sed -n 2p | cut -d '=' -f2 )
		
		options=""
		if [ ! -z "${gallery_video_options[i]}" ]
		then
			options="${gallery_video_options[i]}"
		fi
		
		filters=""
		if [ ! -z "${gallery_video_filters[i]}" ]
		then
			filters=",${gallery_video_filters[i]}"
			filtersfull="-vf ${gallery_video_filters[i]}"
		fi
		
		if [ "$disable_audio" = true ]
		then
			audio="-an"
		else
			audio="-c:a copy"
		fi
		
		if [ "$draft" = true ]
		then
			# if in draft mode, use single pass CRF coding with ultrafast preset
			output_url=$(winpath "$topdir/_site/$url/${resolution[0]}-h264.mp4")
			
			[ -s "$output_url" ] && continue
			
			ffmpeg -loglevel error -i "$filepath" -c:v libx264 -threads "$ffmpeg_threads" $options -vf scale="${resolution[0]}:trunc(ow/a/2)*2$filters" -profile:v high -pix_fmt yuv420p -preset ultrafast -crf 26 $audio -movflags +faststart -f mp4 "$output_url"
		else
			for vformat in "${video_formats[@]}"
			do
				firstpass=false
				for j in "${!resolution[@]}"
				do					
					res="${resolution[$j]}"
					if [ "$width" -ge "$res" ]
					then
						mbit="${bitrate[$j]}"
						mbitmax=$(( mbit*bitrate_maxratio ))
						scaled_height=$(( height*res/width ))
						
						videofile="$res-$vformat."
						
						for k in "${!video_format_extensions[@]}"
						do
							if [ "${video_format_extensions[k]}" = "$vformat" ]
							then
								videofile+="${video_format_extensions[k+1]}"
								break
							fi
						done
						
						[ -s "$topdir/_site/$url/$videofile" ] && continue
						
						output_url=$(winpath "$topdir/_site/$url/$videofile")
						nullpath=$(winpath "/dev/null")
						
						echo -e "\tEncoding $vformat $res x $scaled_height"
						
						# h264 2 pass encode
						if [ "$vformat" = "h264" ]
						then
							if [ "$firstpass" = false ]
							then
								firstpass=true # only need to do first pass once
								ffmpeg -loglevel error -y -i "$filepath" -c:v libx264 -threads "$ffmpeg_threads" $options $filtersfull -profile:v high -pix_fmt yuv420p -preset "$h264_encodespeed" -b:v "$mbit"M -maxrate "$mbitmax"M -bufsize "$mbitmax"M -pass 1 -an -f mp4 "$nullpath" || continue 2 # if we can't encode the video, skip this file entirely. Possibly not a video file
							fi
							
							ffmpeg -loglevel error -i "$filepath" -c:v libx264 -threads "$ffmpeg_threads" $options -vf scale="$res:trunc(ow/a/2)*2$filters"  -profile:v high -pix_fmt yuv420p -preset "$h264_encodespeed" -b:v "$mbit"M -maxrate "$mbitmax"M -bufsize "$mbitmax"M -pass 2 $audio -movflags +faststart -f mp4 "$output_url"
						
						# VP9 2 pass encode
						elif [ "$vformat" = "vp9" ]
						then
							if [ "$firstpass" = false ]
							then
								firstpass=true # only need to do first pass once
								ffmpeg -loglevel error -y -i "$filepath" -c:v libvpx-vp9 -threads "$ffmpeg_threads" $options $filtersfull -pix_fmt yuv420p -speed 4 -b:v "$mbit"M -maxrate "$mbitmax"M -bufsize "$mbitmax"M -pass 1 -an -f webm "$nullpath" || continue 2 # if we can't encode the video, skip this file entirely. Possibly not a video file
							fi
							
							ffmpeg -loglevel error -i "$filepath" -c:v libvpx-vp9 -threads "$ffmpeg_threads" $options -vf scale="$res:trunc(ow/a/2)*2$filters" -pix_fmt yuv420p -speed "$vp9_encodespeed" -b:v "$mbit"M -maxrate "$mbitmax"M -bufsize "$mbitmax"M -pass 2 $audio -f webm "$output_url"
						
						# VP8 2 pass encode
						elif [ "$vformat" = "vp8" ]
						then
							if [ "$firstpass" = false ]
							then
								firstpass=true # only need to do first pass once
								ffmpeg -loglevel error -y -i "$filepath" -c:v libvpx -threads "$ffmpeg_threads" $options $filtersfull -pix_fmt yuv420p -b:v "$mbit"M -maxrate "$mbitmax"M -bufsize "$mbitmax"M -pass 1 -an -f webm "$nullpath" || continue 2 # if we can't encode the video, skip this file entirely. Possibly not a video file
							fi
							
							ffmpeg -loglevel error -i "$filepath" -c:v libvpx -threads "$ffmpeg_threads" $options -vf scale="$res:trunc(ow/a/2)*2$filters" -pix_fmt yuv420p -b:v "$mbit"M -maxrate "$mbitmax"M -bufsize "$mbitmax"M -pass 2 $audio -f webm "$output_url"
						
						# Theora 1 pass encode
						elif [ "$vformat" = "ogv" ]
						then
							ffmpeg -loglevel error -i "$filepath" -c:v libtheora -threads "$ffmpeg_threads" $options -vf scale="$res:trunc(ow/a/2)*2$filters" -pix_fmt yuv420p -b:v "$mbit"M -maxrate "$mbitmax"M -bufsize "$mbitmax"M $audio "$output_url"
						fi
					fi
				done
			done
		fi
		
		output_url=""
		
		ffmpeg -loglevel error -i "$filepath" $options -vf "select=gte(n\,1)$filters" -vframes 1 -qscale:v 2 "$scratchdir/temp.jpg"
		image="$scratchdir/temp.jpg"
	fi
	
	# generate static images for each resolution
	width=$(identify -format "%w" "$image")
	
	options=""
	if [ ! -z "${gallery_image_options[i]}" ]
	then
		options="${gallery_image_options[i]}"
	fi
	
	if [ "${gallery_type[i]}" = 1 ]
	then
		options="" # don't apply image options to a video
	fi
	
	count=0
	
	for res in "${resolution[@]}"
	do
		((count++))
		[ -e "$topdir/_site/$url/$res.jpg" ] && continue
		
		# only downscale original image
		if [ "$width" -ge "$res" ] || [ "$count" -eq "${#resolution[@]}" ]
		then
			convert -size "$res"x"$res" "$image" -resize "$res"x"$res" -quality "$jpeg_quality" +profile '*' $options "$topdir/_site/$url/$res.jpg"
		fi
	done
	
	# write zip file
	if [ "$download_button" = true ] && [ ! -e "$topdir/_site/$url/${gallery_url[i]}.zip" ]
	then
		mkdir "$scratchdir/zip"
		
		if [ "${gallery_type[i]}" = 2 ]
		then
			filezip="$sequencevideo"
		else
			filezip="${gallery_files[i]}"
		fi
		
		filename=$(basename "$filezip")
		cp "${gallery_files[i]}" "$scratchdir/zip/$filename"
		echo "$download_readme" > "$scratchdir/zip/readme.txt"
		
		chmod -R 740 "$scratchdir/zip"
		
		cd "$scratchdir/zip" && zip -r "$topdir/_site/$url/${gallery_url[i]}.zip" ./
		cd "$topdir"
	fi
	
	rm -rf "${scratchdir:?}/"*
done

# copy resources to _site
rsync -av --exclude="template.html" --exclude="post-template.html" "$scriptdir/$theme_dir/" "$topdir/_site/" >/dev/null

cleanup
