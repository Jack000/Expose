var video_formats={
	h265: { extension: "mp4", type: "video/mp4; codecs=hev1.1.2.L93.B0"},
	h264: { extension: "mp4", type: "video/mp4"},
	vp9: { extension: "webm", type: "video/webm; codecs=vp9"},
	vp8: { extension: "webm", type: "video/webm; codecs=vp8"},
	ogv: { extension: "ogv", type: "video/ogg"}
};

var resolution = [];
var resourcepath;

$(document).ready(function(){
	resourcepath = $('body').data('respath');
	
	// set slide heights to prevent reflow
	var mainwidth = $('#main').width();
	
	$('.image.index1').css('width','125%'); // first image is masthead, do not allow content override
	
	$('.image').each(function(){
		$(this).css('padding-top', (100*$(this).data('maxheight')/$(this).data('maxwidth'))*($(this).width()/mainwidth) + '%');
	});
	
	$.each(String($('body').data('resolution')).split(" "),function(i, v){
		if(v){
			resolution.push(parseInt(v));
		}
	});
	
	resolution.sort(function(a, b){return a-b;});
	
	// remove empty posts
	$('.post').filter(function() {
        return $.trim($(this).text()) === '' && $(this).children().length === 0;
    }).remove();
	
	// set ui colors to first image
	var color = $('.image.index1').data('color6');
	$('#top .author img, .arrow_circle').css('border-color',color);
	$('#top .title .subscript, #nav_toggle').css('color',color);
	
	$('.image.index1').append('<div class="overlay" style="background-color: '+$('.image.index1').data('color2')+'"></div>');
	$('.image').not('.index1, .fullwidth').click(function(){
		// full screen mode
		$('#fullscreen').addClass('active').append($(this).find('img').clone());
		var img = $('#fullscreen img');
		
		var imgwidth = img.prop('width');
		var imgheight = img.prop('height');
		
		var screenwidth = $(window).width();
		var screenheight = $(window).height();
		
		// check aspect ratio
		if(imgwidth/imgheight > screenwidth/screenheight){
			img.css('width','100%').css('height','auto').css('margin-top',(0.5*(screenheight-img.height()))+'px');
		}
		else{
			img.css('height','100%').css('width','auto');
		}
		
		width = img.width();
		var url = resourcepath + img.data('url');
		var maxwidth = $(this).data('maxwidth');
		var displaywidth = maxwidth;
		$.each(resolution, function(i, v){
			if(v >= width && v <= maxwidth && v < displaywidth){
				displaywidth = v;
			}
		});
		
		img.prop('src',url+'/'+displaywidth+'.jpg');
		
		// set video
		$('#fullscreenvideo').addClass('active').append($(this).find('video, .progress').clone());
		var video = $('#fullscreenvideo video');
		if(imgwidth/imgheight > screenwidth/screenheight){
			video.css('width','100%').css('height','auto').css('margin-top',(0.5*(screenheight-video.height()))+'px');
		}
		else{
			video.css('height','100%').css('width','auto');
		}
		
		$('#fullscreenvideo video source').each(function(){
			$(this).prop('src', url+'/'+displaywidth+'-'+$(this).data('format')+'.'+$(this).data('extension'));
		});
		
		$('#fullscreenvideo .progress').addClass('active');
		
		if(video.length > 0){
			video.get(0).addEventListener('progress', function() {
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
		
		$('#fullscreen').css('background-color',$(this).data('color1'));
		
		return false;
	});
	
	$('#fullscreen, #fullscreenvideo').click(function(){
		$('#fullscreen, #fullscreenvideo').empty();
		$('#fullscreen, #fullscreenvideo').removeClass('active');
	});
	
	if($('#nav li').length <= 1){
		$('#nav_toggle').remove();
		$('#top .author').addClass('center').css('margin-left','-'+(0.5*$('.author').width())+'px');
	}
	else{	
		$('#nav_toggle').click(function(){
			if($('#top').hasClass('active')){
				$('#top').removeClass('active');
				$('#top').css('background','transparent');
				$('#nav_toggle .moretext').text($('#nav_toggle .moretext').data('text'));
			}
			else{
				$('#top').css('background',$('.image.index1').data('color1'));
				$('#top').addClass('active');
				$('#nav_toggle .moretext').data('text', $('#nav_toggle .moretext').text()).text('Hide');
			}
		});
		
		$('#nav li.gallery').not('.active').each(function(){
			$(this).append('<img src="'+$(this).find('a').prop('href')+'/'+$(this).data('image')+'/'+resolution[0]+'.jpg" />');
		});
	}
	
	scrollcheck();
});

function scrollcheck(){
	$('.image').each(function(){
		
		var overlap = findoverlap(this);
		if( overlap > -1){
			var img = $(this).find('img');
			var url = resourcepath + img.data('url');
			
			var width = img.width();
			var maxwidth = $(this).data('maxwidth');
			var displaywidth = maxwidth;
			$.each(resolution, function(i, v){
				if(v >= width && v <= maxwidth && v < displaywidth){
					displaywidth = v;
				}
			});
			
			img.prop('src',url+'/'+displaywidth+'.jpg');
			$(this).removeClass('blank');
			
			// videos
			if($(this).data('type') == 'video'){
				if($(this).find('video').length === 0){
					var formats = String($(this).data("videoformats")).split(" ");
					if(formats.length > 0){
						var vidstring = '<div class="progress active"><div class="bar" style="background-color: '+$(this).data('textcolor')+'"></div></div>';
						vidstring += '<video poster="'+url+'/'+displaywidth+'.jpg" alt="" autoplay="autoplay" loop="loop" preload="auto">';
						
						$.each(formats, function(i, v){
							if(v){
								vformat = video_formats[v];
								var sourceurl = url+'/'+displaywidth+'-'+v+'.'+vformat.extension;
								vidstring += '<source src="'+sourceurl+'" type="'+vformat.type+'" data-source="'+sourceurl+'" data-format="'+v+'" data-extension="'+vformat.extension+'"></source>';
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
		else{
			// keeping all videos takes too much memory, reset as we go along
			$(this).find('video, .progress').remove();
		}
	});
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

function findoverlap(elem)
{
	var winHeight = $(window).height();
    var docViewTop = $(window).scrollTop();
    var docViewBottom = docViewTop + winHeight;

    var elemTop = $(elem).offset().top;
	var elemHeight = $(elem).outerHeight();
    var elemBottom = elemTop + elemHeight;
	
	var overlap = (Math.min(elemBottom, docViewBottom) - Math.max(elemTop, docViewTop));
	return overlap/(winHeight);
}
