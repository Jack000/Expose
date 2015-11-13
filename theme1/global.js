var loadnext = 5; // preload next 5 slides
var loadprev = 2; // keep previous 2 slides in case user scrolls up

var videoloadnext=2; // preload videos less

var resourcepath;

var current_resolution = 1920;
var resolution = [];

var disqus_loaded = false;
var current_slide = $('.slide').get(0);

var video_formats={
	h265: { extension: "mp4", type: "video/mp4; codecs=hev1.1.2.L93.B0"},
	h264: { extension: "mp4", type: "video/mp4"},
	vp9: { extension: "webm", type: "video/webm; codecs=vp9"},
	vp8: { extension: "webm", type: "video/webm; codecs=vp8"},
	ogv: { extension: "ogv", type: "video/ogg"}
};

function drawtext(){
	var screen_width = $(window).width();
	
	// set font size based on actual resolution, normalized at 14px/22px for 720
	var fontsize = Math.floor(14*(screen_width/1280));
	var lineheight = Math.floor(22*(screen_width/1280));
	
	if(fontsize < 11){
		fontsize = 11;
	}
	
	if(lineheight < 14){
		lineheight = 14;
	}
	
	$('body').css('font-size',fontsize+'px');
	$('body').css('line-height',lineheight+'px');
	
	// polygon boundary feature
	$('.slide').each(function(){
		var polygon = $(this).data('polygon');
		
		if(polygon && $.isArray(polygon) && polygon.length >= 3){
			fillpolygon($(this).find('.content').eq(0),polygon);
		}
	});
}

function redrawtext(){
	$('.slide .polygon').remove();
	$('.slide .content').show();
	
	drawtext();
}

$(document).ready(function(){

	// set slide heights to prevent reflow
	$('.slide').each(function(){
		$(this).css('padding-top', (100*$(this).data('imageheight')/$(this).data('imagewidth')) + '%');
	});
	
	resourcepath = $('body').data('respath');
	
	// detect resolution
	var saved_width = $.cookie('resolution');
	var screen_width = $(window).width();
	
	drawtext();
	
	// build resolution selector
	$.each(String($('body').data('resolution')).split(" "),function(i, v){
		if(v){
			resolution.push(parseInt(v));
		}
	});
	
	resolution.sort(function(a, b){return b-a;});
	
	var selector = '';
	$.each(resolution, function(i, v){
		// use 16:9 XXXp conventions for labels. eg. 1080p, 1440p etc
		var label;
		
		if(i == resolution.length-1 && v <= 1024){
			label = 'mobile';
		}
		else if(v == 3840){
			label = '4K';
		}
		else{
			var h = parseInt((9/16)*v);
			label = h+'p';
		}
		
		selector += '<li data-res="'+v+'"><a href="#">'+label+'</a></li>';
	});
	
	selector = '<ul>'+selector+'</ul>';
	
	$('#resolution').append(selector);
		
	// resolution select
	
	$('#resolution ul li').click(function(){
		var new_resolution = $(this).data('res');
		
		if(current_resolution != new_resolution){
			current_resolution = new_resolution;
			// update all urls
			$('.slide').each(function(index){
				var set_res = current_resolution;
				if(parseInt($(this).data('imagewidth')) < current_resolution){
					set_res = parseInt($(this).data('imagewidth'));
				}
				var url = resourcepath + $(this).find('img.image').data('url');
				$(this).find('img.image').not('.blank').prop('src',url+'/'+set_res+'.jpg');
			});
			
			// set ui
			$('#resolution li.active').removeClass('active');
			$(this).addClass('active');
			
			$.cookie('resolution', current_resolution,  { expires: 7, path: '/' });
		}
		
		$('#resbutton .restext').text($(this).find('a').text());
		
		$('#resolution').removeClass('active');
		return false;
	});
	
	// click away from dialog
	$('body').click(function(e) {
	    if (!$(e.target).is('#resolution')) {
	        $('#resolution').removeClass('active');
	    }
	    if (!$(e.target).is('#share')) {
	        $('#share').removeClass('active');
	    }
	});
  	
  	if(saved_width){
  		// used cookie value if set
  		$('#resolution li').each(function(i){
			var val = parseInt($(this).data('res'));
			if(saved_width == val){
				$(this).trigger('click');
				$(this).addClass('active');
				return false;
			}
		});
  	}
  	else{
		// assume large->small order
		var found = false;
		$('#resolution ul li').each(function(i){
			var val = parseInt($(this).data('res'));
			if(screen_width >= val-50){
				$(this).trigger('click');
				$(this).addClass('active');
				found=true;
				return false;
			}
		});
		
		if(!found){
			$('#resolution li').last().trigger('click');
		}
	}
		
	scrollcheck();
	
	// add back hover behavior erased by color changes
	$('#sidebar a, #share a, #resolution a').not('#nav .active a').mouseenter(function(){
		var color = $(this).css('color');
		$(this).css('color','#ffffff');
		$(this).data('prevcolor',color);
	}).mouseleave(function(){
		var color = $(this).data('prevcolor');
		if(color){
			$(this).css('color',color);
		}
	});
	
	// browser detect
	if($.browser.webkit){
		$('.icon').addClass('webkit');
	}
	
	$('#sharebutton').click(function(){
		if($('#share').hasClass('active')){
			$('#share').removeClass('active');
		}
		else{
			$('#share').addClass('active');
		}
		$('#resolution').removeClass('active');
		return false;
	});
	
	$('#resbutton').click(function(){
		if($('#resolution').hasClass('active')){
			$('#resolution').removeClass('active');
		}
		else{
			$('#resolution').addClass('active');
		}
		$('#share').removeClass('active');
		return false;
	});

	// download current
	$('#download').click(function(){
		var url = $(current_slide).find('img.image').data('url');
		window.open(resourcepath + url+'/'+url+'.zip');
		return false;
	});
	
	// text toggle
	$('#textbutton').click(function(){
		if($(this).hasClass('active')){
			$('.post').addClass('hidden');
			$(this).removeClass('active');
			$(this).find('.text').text('show text');
		}
		else{
			$('.post').removeClass('hidden');
			$(this).addClass('active');
			$(this).find('.text').text('hide text');
		}
		
		return false;
	});
	
	// add marker
	var mheight = 100/$('.slide').length;
	$('.slide').each(function(i, v){
		var color1 = $(this).data('color1');
		var color7 = $(this).data('color7');
		if(!color1){
			color1 = '#000';
		}
		if(!color7){
			color7 = '#fff';
		}
		$('#marker').append('<li style="background-color: '+color1+'; height: '+mheight+'%"><a href="#'+(i+1)+'" style="background-color: '+color7+'"></a></li>');
	});
	
});

function scrollcheck(){

	// current slide is the one with the largest overlap with screen
	var new_slide = false;
	var maxoverlap = 0;
	$('.slide').each(function(){
		var overlap = findoverlap(this);				
	
		if(overlap > maxoverlap){
			maxoverlap = overlap;
			new_slide = this;
		}
	});
	
	if(new_slide && new_slide != current_slide){
		current_slide = new_slide;
		var index = $('.slide').index(current_slide);
		
		$('.slide .image').removeClass('active');
		$('.slide video').removeClass('active');
		
		// load next N slides as per config
		// remove videos from dom as we scroll past
		$('.slide').each(function(i){
			var img = $(this).find('img.image');
			
			var set_res = current_resolution;
			if(parseInt($(this).data('imagewidth')) < current_resolution){
				set_res = parseInt($(this).data('imagewidth'));
			}
			
			if(i-index >= -loadprev && i-index<=loadnext){
				var url = resourcepath + img.data('url');
				if($(this).data('type') == 'video'){
					if(i-index >= 0 && i-index <= videoloadnext){ // preload next N videos
						if($(this).find('video').length === 0){

							var formats = String($(this).data("videoformats")).split(" ");
							if(formats.length > 0){
								var vidstring = '<div class="progress active"><div class="bar" style="background-color: '+$(this).parent().data('textcolor')+'"></div></div>';
								vidstring += '<video class="image" poster="' + url+'/'+set_res+'.jpg" alt="" autoplay="autoplay" loop="loop" preload="auto" width="'+$(this).width()+'" height="'+$(this).outerHeight()+'">';
								
								$.each(formats, function(i, v){
									if(v){
										vformat = video_formats[v];
										var sourceurl = url+'/'+set_res+'-'+v+'.'+vformat.extension;
										vidstring += '<source src="'+sourceurl+'" type="'+vformat.type+'" data-extension="'+(v+'.'+vformat.extension)+'"></source>';
									}
								});
								
								vidstring += '</video>';
								
								$(this).append(vidstring);
								$(this).find('video').get(0).addEventListener('progress', function() {
									try{
										var percent = 100 * this.buffered.end(0) / this.duration;
										$(this).parent().find('.progress .bar').css('width',percent+'%');
										if(percent > 90){
											$(this).parent().find('.progress').removeClass('active');
										}
									}
									catch (e) {}
								});
							}
						}
						
					}
				}
				img.prop('src',url+'/'+set_res+'.jpg').removeClass('blank');
			}
			else{
				// keeping all videos takes too much memory, reset as we go along
				$(this).find('img.image').addClass('blank');
				$(this).find('video, .progress').remove();
			}
		});
		
		$(current_slide).find('.image').addClass('active');

		$(current_slide).nextAll().filter('.slide').slice(0,5).find('img.image').addClass('active');
		$(current_slide).prevAll().filter('.slide').slice(0,2).find('img.image').addClass('active');
		
		// set custom colors
		var sidebackground = $(current_slide).data('color2');
		if(sidebackground){
			$('#sidebar .background').css('background-color',sidebackground);
		}
		
		var resbackground = $(current_slide).data('color3');
		if(resbackground){
			$('#resolution').css('background-color',resbackground);
		}
		
		var sharebackground = $(current_slide).data('color4');
		if(sharebackground){
			$('#share').css('background-color',sharebackground);
		}
		
		var highcolor = $(current_slide).data('textcolor');
		var sidecolor = $(current_slide).data('color6');
		if(sidecolor){
			$('#sidebar, #sidebar a, #share a, #resolution a').css('color',sidecolor);
			$('#sidebar .active a, #resolution .active a').css('color',highcolor).css('border-color', highcolor);
		}
		
		$('#sidebar .icon.webkit, #share .icon.webkit').css('background-color',sidecolor);
				
		// highlight nav
		
		if(index >= 0){
			$('#marker li.active').removeClass('active');
			$('#marker li').eq(index).addClass('active');
		}
		
		return false;
	}
}

_now = Date.now || function() { return new Date().getTime(); };

throttle = function(func, wait, options) {
    var context, args, result;
    var timeout = null;
    var previous = 0;
    options || (options = {});
    var later = function() {
      previous = options.leading === false ? 0 : _now();
      timeout = null;
      result = func.apply(context, args);
      context = args = null;
    };
    return function() {
      var now = _now();
      if (!previous && options.leading === false) previous = now;
      var remaining = wait - (now - previous);
      context = this;
      args = arguments;
      if (remaining <= 0) {
        clearTimeout(timeout);
        timeout = null;
        previous = now;
        result = func.apply(context, args);
        context = args = null;
      } else if (!timeout && options.trailing !== false) {
        timeout = setTimeout(later, remaining);
      }
      return result;
    };
  };

var throttled = throttle(scrollcheck, 700);
$(window).scroll(throttled);

var redrawtext_throttled = throttle(redrawtext, 1000);
$(window).resize(redrawtext_throttled);

function findoverlap(elem)
{
	var winHeight = $(window).height();
    var docViewTop = $(window).scrollTop();
    var docViewBottom = docViewTop + winHeight;

    var elemTop = $(elem).offset().top;
	var elemHeight = $(elem).outerHeight();
    var elemBottom = elemTop + elemHeight;
	
	var overlap = (Math.min(elemBottom, docViewBottom) - Math.max(elemTop, docViewTop));
	if(overlap > 0){
		return overlap/(winHeight);
	}
    return 0;
}

// given content element and a polygon definition, fill the polygon with content text and hide original content
function fillpolygon(content, polygon){
	if(!polygon || polygon.length < 3){
		return false;
	}
	
	// loop back to first vertex
	polygon.push(polygon[0]);
	
	var fill = $('<div class="polygon" />');
	content.after(fill);
	var cwidth = content.width();
	var cheight = content.height();

	content.contents().each(function(){
		var isblock = false;
		var samefont = true;
		if(this.nodeType == 1){
			isblock = $(this).css("display") == "block";
			samefont = $(content).css("font-size") == $(this).css("font-size");
		}

		// stuff like h1 h2 etc will be difficult to wrap, put them on the first intercept and don't attempt to wrap
		var coords;
		if(this.nodeType == 1 && isblock && !samefont){
			// html, no end clip
			var clone = $(this).clone();
			fill.append(clone);
			
			coords = intersect(100*(clone.position().top/content.height()), polygon);
			
			if(coords.length === 0){
				coords = 0;
			}
			else{
				coords = coords.shift();
			}
			if(coords > 0){
				clone.prepend('<span class="filler" style="width: '+coords+'%"></span>');
			}
		}
		else if(this.nodeType == 3 || this.nodeType == 1){ // text node
			
                        var text;
                        
			if(this.nodeType == 3){
				text = this.nodeValue.trim();
			}
			else{
				text = $(this).text();
			}
			
			if(!text){
				return true;
			}
			
			var words = text.match(/\S+/g);

			while(words.length > 0){
				// wrap in span so we can get dimensions
				var span;
				if(this.nodeType == 3 || isblock){
					span = $('<span class="line">&nbsp;</span>');
				}
				else{
					span = $(this).clone().text('');
				}
				
				fill.append(span);
				
				var left = 100*(span.position().left/cwidth);
				var top = 100*(span.position().top/cheight);
				
				if(top > 100){
					span.remove();
					return false;
				}
				
				var min = left;
				var max = 100;
				
				coords = intersect(top, polygon);
				
				if(!coords || coords.length < 2){
					min = 0;
					max = 100;
				}
				
				// depending on the x position of the span, we may not care about certain intercepts
				for(var i=0; i<coords.length; i += 2){
					if(coords[i] >= left){
						min = coords[i];
						max = coords[i+1];
						break;
					}
				}				
				
				// shift to min
				span.before('<span class="filler" style="width: '+(min-left)+'%" />');
				
				// type out text until wraps
				for(i=1; i<=words.length; i++){
					var height = span.height();
					
					span.text(words.slice(0, i).join(' '));
					
					var width = 100*(span.width()/cwidth);
					if(min+width > max){
						break;
					}
				}
				
				if(coords.length < 3 || min+max > 100){
					fill.append('<br />');
				}
								
				words = words.slice(i);
			}
			
			if(this.nodeType != 3 && isblock){
				fill.append('<br />');
			}
		}
		else if(this.nodeType == 1){
			fill.append($(this).clone());
		}
	});
	
	content.hide();
}

// find all intersections between a horizontal line at height, and the given polygon
function intersect(height, polygon){
	if(polygon.length < 3){
		return false;
	}
	
	var points = [];
	for(var i=0; i<polygon.length-1; i++){
		var p1 = polygon[i];
		var p2 = polygon[i+1];
		
		// horizontal line
		if(p1.y == p2.y && height == p1.y){
			if(p1.x < p2.x){
				points.push(p1.x);
			}
			else{
				points.push(p2.x);
			}
		}		
		if(p1.y == height && $.inArray(p1.x, points) < 0){
			points.push(p1.x);
		}
		if(p2.y == height && $.inArray(p2.x, points) < 0){
			points.push(p2.x);
		}
		if(p1.y < height && p2.y > height){
			points.push(p1.x + ((height-p1.y)/(p2.y-p1.y))*(p2.x-p1.x));
		}
		else if(p1.y > height && p2.y < height){
			points.push(p2.x + ((height-p2.y)/(p1.y-p2.y))*(p1.x-p2.x));
		}
	}
	
	
	// sort intercepts left to right
	points.sort(function(a,b){
		return a-b;
	});
	
	return points;
}

function pad(n, width, z) {
  z = z || '0';
  n = n + '';
  return n.length >= width ? n : new Array(width - n.length + 1).join(z) + n;
}

// add back browser detect
jQuery.uaMatch = function( ua ) {
ua = ua.toLowerCase();
var match = /(chrome)[ \/]([\w.]+)/.exec( ua ) ||
    /(webkit)[ \/]([\w.]+)/.exec( ua ) ||
    /(opera)(?:.*version|)[ \/]([\w.]+)/.exec( ua ) ||
    /(msie) ([\w.]+)/.exec( ua ) ||
    ua.indexOf("compatible") < 0 && /(mozilla)(?:.*? rv:([\w.]+)|)/.exec( ua ) ||
    [];
return {
    browser: match[ 1 ] || "",
    version: match[ 2 ] || "0"
};
};
if ( !jQuery.browser ) {
matched = jQuery.uaMatch( navigator.userAgent );
browser = {};
if ( matched.browser ) {
    browser[ matched.browser ] = true;
    browser.version = matched.version;
}
// Chrome is Webkit, but Webkit is also Safari.
if ( browser.chrome ) {
    browser.webkit = true;
} else if ( browser.webkit ) {
    browser.safari = true;
}
jQuery.browser = browser;
}
