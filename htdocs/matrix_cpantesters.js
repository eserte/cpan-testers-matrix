// Copied from bbbike/html/sprintf.js

// From http://jan.moesen.nu/
// Found at http://jan.moesen.nu/code/javascript/sprintf-and-printf-in-javascript/
// Fixes by Slaven Rezic
function sprintf()
{
    if (!arguments || arguments.length < 1 || !RegExp)
    {
	return "";
    }
    var str = arguments[0];
    var processed = "";
    var re = /([^%]*)%('.|0|\x20)?(-)?(\d+)?(\.\d+)?(%|b|c|d|u|f|o|s|x|X)(.*)/; // '
    var a = b = [], numSubstitutions = 0, numMatches = 0;
    while ((a = re.exec(str)))
    {
	var leftpart = a[1], pPad = a[2], pJustify = a[3], pMinLength = a[4];
	var pPrecision = a[5], pType = a[6], rightPart = a[7];
	
	processed += leftpart;

	//alert(a + '\n' + [a[0], leftpart, pPad, pJustify, pMinLength, pPrecision);

	numMatches++;
	if (pType == '%')
	{
	    subst = '%';
	}
	else
	{
	    numSubstitutions++;
	    if (numSubstitutions >= arguments.length)
	    {
		alert('Error! Not enough function arguments (' + (arguments.length - 1) + ', excluding the string)\nfor the number of substitution parameters in string (' + numSubstitutions + ' so far).');
	    }
	    var param = arguments[numSubstitutions];
	    var pad = '';
	    if (pPad && pPad.substr(0,1) == "'") pad = leftpart.substr(1,1);
	    else if (pPad) pad = pPad;
	    var justifyRight = true;
	    if (pJustify && pJustify === "-") justifyRight = false;
	    var minLength = -1;
	    if (pMinLength) minLength = parseInt(pMinLength);
	    var precision = -1;
	    if (pPrecision && pType == 'f') precision = parseInt(pPrecision.substring(1));
	    var subst = param;
	    if (pType == 'b') subst = parseInt(param).toString(2);
	    else if (pType == 'c') subst = String.fromCharCode(parseInt(param));
	    else if (pType == 'd') subst = parseInt(param) ? parseInt(param) : 0;
	    else if (pType == 'u') subst = Math.abs(param);
	    else if (pType == 'f') subst = (precision > -1) ? Math.round(parseFloat(param) * Math.pow(10, precision)) / Math.pow(10, precision): parseFloat(param);
	    else if (pType == 'o') subst = parseInt(param).toString(8);
	    else if (pType == 's') subst = param;
	    else if (pType == 'x') subst = ('' + parseInt(param).toString(16)).toLowerCase();
	    else if (pType == 'X') subst = ('' + parseInt(param).toString(16)).toUpperCase();
	}
	subst = subst.toString();

	if (subst.length < minLength) {
	    var padLength = minLength - subst.length;
	    if (!justifyRight) {
		for(var i=0; i<padLength; i++) {
		    subst += pad;
		}
	    } else {
		for(var i=0; i<padLength; i++) {
		    subst = pad + subst;
		}
	    }
	}

	processed += subst;
	str = rightPart;
    }

    if (str.length > 0) {
	processed += str;
    }
    return processed;
}

//////////////////////////////////////////////////////////////////////

function DynamicDate(epoch, element_id, options) {
    this.epoch = epoch;
    this.date_formatted = null;
    this.element_id = element_id;
    this.debug = options && options.debug ? true : false;
    this.no_seconds = options && options.no_seconds ? true : false;

    this.update_date = function() {
	var now_d = new Date;
	var elapsed = now_d.getTime()/1000 - this.epoch;
	var s = this.date_formatted;
	var next_update = 60;
	if (this.debug) {
	    s += " (" + Math.floor(elapsed) + " seconds ago)";
	    next_update = 5;
	} else if (elapsed >= 86400*365.25*2) {
	    s += " (" + Math.floor(elapsed/(86400*365.25)) + " years ago)";
	} else if (elapsed >= 86400*2) {
	    s += " (" + Math.floor(elapsed/86400) + " days ago)";
	} else if (elapsed >= 86400) {
	    s += " (a day ago)";
	} else if (elapsed >= 3600*2) {
	    s += " (" + Math.floor(elapsed/3600) + " hours ago)";
	} else if (elapsed >= 3600) {
	    s += " (an hour ago)";
	} else if (elapsed >= 60*2) {
	    s += " (" + Math.floor(elapsed/60) + " minutes ago)";
	} else if (elapsed >= 60) {
	    s += " (a minute ago)";
	} else {
	    next_update = 1;
	}
	var node = document.getElementById(this.element_id);
	if (node) {
	    node.innerHTML = s;
	    var this_dynamic_date = this;
	    window.setTimeout(function () { this_dynamic_date.update_date() }, next_update*1000);
	}
    };

    var date = new Date(this.epoch*1000);
    this.date_formatted = sprintf("%04d-%02d-%02d %02d:%02d" + (this.no_seconds ? "" : ":%02d"),
				  date.getFullYear(), date.getMonth()+1, date.getDate(),
				  date.getHours(), date.getMinutes(), date.getSeconds());
    var date_string = date.toString();
    if (date_string.match(/\((.+?)\)$/)) {
        this.date_formatted += " " + RegExp.$1;
    } else {
        var tzOffset = date.getTimezoneOffset();
        var tzOffsetString;
        if (tzOffset == 0) {
	    tzOffsetString = 'UTC';
        } else {
	    var sgn = tzOffset > 0 ? '-' : '+';
	    tzOffset = Math.abs(tzOffset);
	    var tzOffsetH = Math.floor(tzOffset/60);
	    var tzOffsetM = tzOffset%60;
	    tzOffsetString = 'UTC' + sgn + tzOffsetH + (tzOffsetM == 0 ? '' : ':' + sprintf("%02d", tzOffsetM));
        }
        this.date_formatted += " " + tzOffsetString;
    }
    this.update_date();
}

function rewrite_server_datetime() {
    var elems = document.querySelectorAll("*[data-time]");
    for (var i = 0; i < elems.length; i++) {
	var elem = elems[i];
	var d = new Date(elem.getAttribute("data-time")*1000);
	elem.innerHTML = d.toLocaleString();
    }
}

//////////////////////////////////////////////////////////////////////

function reset_location_hash() {
    if (location.hash != "" && location.hash != "#") {
	location.replace("#");
    }
}

//////////////////////////////////////////////////////////////////////

function shift_reload_alternative() {
    var elem = document.querySelector("#shift_reload");
    if (elem) {
       elem.innerHTML = elem.innerHTML + ' or click <a href="javascript:window.location.reload(true)">here</a>';
    }
}

//////////////////////////////////////////////////////////////////////

function add_json_download_link(dist) {
    var u = "https://www.cpantesters.org";
    u += "/show";
    u += "/";
    u += dist;
    u += ".json";
    document.write('<a class="sml" href="' + u + '">raw JSON data</a>');
}
