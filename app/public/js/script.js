function $(id){
	return document.getElementById(id)
}


//************** ON CHANGE EVENTS ***************//
function queryType(){
	var x = $("query_select").value;
	$("demo").innerHTML = "you selected: " + x;
}
function arrlSet(cb){
	arrl_expire = $('arrl_expire');
	if (cb.checked){
		arrl_expire.disabled = "";
		arrl_expire.focus();
	}else{
		arrl_expire.disabled = "disabled";
		arrl_expire.value = "";
		arrl_expire.style.borderColor = 'black';
		arrl_expire.setAttribute('isInValid','');
	}
}

function validateArrlExpDate(textbox){
	var date = textbox.value.trim();
	var datePattern = /^\d{4}-\d{2}-\d{2}$/
	if(!date.match(datePattern)){
		textbox.style.borderColor = 'red';
		textbox.setAttribute('isInValid','invalid');
	}else{
		textbox.style.borderColor = 'black';
		textbox.setAttribute('isInValid','');
	}
}
function validatePh(textbox){
	var phone = textbox.value.trim();
	var phonePattern = /^\d{3}-\d{3}-\d{4}$/;
	if (phone == ""){
		textbox.style.borderColor = 'black';
		textbox.setAttribute('isInValid','');
		return 0;
	}
	if(!phone.match(phonePattern)){
		textbox.style.borderColor = 'red';
		textbox.setAttribute('isInValid','invalid');
	}else{
		textbox.style.borderColor = 'black';
		textbox.setAttribute('isInValid','');
	}
}
function validateZip(textbox){
	var zip = textbox.value.trim();
	if (zip == ""){
		textbox.style.borderColor = 'black';
		textbox.setAttribute('isInValid','');
		return 0;
	}
	var zipPattern = /^\d{5}(-\d{4})?$/;
	if(!zip.match(zipPattern)){
		textbox.style.borderColor = 'red';
		textbox.setAttribute('isInValid','invalid');
	}else{
		textbox.style.borderColor = 'black';
		textbox.setAttribute('isInValid','');
	}
}
function validateEmail(textbox){
	var email = textbox.value.trim();
	if (email == ""){
		textbox.style.borderColor = 'black';
		textbox.setAttribute('isInValid','');
		return 0;
	}
	//a close approximation
	var emailPattern = /^\w[-.\w]*@[-a-z0-9]+(\.[-a-z0-9]+)*\.(com|edu|info|mil|net|org|biz|[a-z][a-z])$/i;
	if(!email.match(emailPattern)){
		textbox.style.borderColor = 'red';
		textbox.setAttribute('isInValid','invalid');
	}else{
		textbox.style.borderColor = 'black';
		textbox.setAttribute('isInValid','');
	}
}
function validateQueryForm(){
	var formInvalid = true
	var queryType = $(query_select);
	if (queryType == "paid_up"){
		//check to see radio button selected
	}
	if (queryType == "mbr_type"){
		//check to see radio button selected
	}
}
function validateAssignRoleForm(){
	var roles = document.querySelectorAll('input[type="checkbox"]');
	//test to see if at least one checkbox is checked
	var checkedOne = Array.prototype.slice.call(roles).some(x => x.checked);
	if (checkedOne){//$("roles").length > 0
		document.auRoles.submit();
	} else {
		alert("At least one Role must be selected");
		return false;
	}
}
function validateMbrPayForm(){
	var paid_up = $("paid_yr_field").value;
	var mbr_type = $("mbr_type").value;
	yes = confirm("Is this correct?\n\n" + "Member type " + mbr_type + "\nPaid through " + paid_up);
	if (yes){
		return true;
	}else{
		return false;
	}
}
function validateMbrForm(){
	var arrlDate = $("arrl_expire").getAttribute('isInValid');
	var phoneHome = $("phh").getAttribute('isInValid');
	var phoneWork = $("phw").getAttribute('isInValid');
	var phoneMobile = $("phm").getAttribute('isInValid');
	var email = $("email").getAttribute('isInValid');
	var zip = $("zip").getAttribute('isInValid');
	var checkArray = []
	checkArray["phh"] = phoneHome;
	checkArray["phw"] = phoneWork;
	checkArray["phm"] = phoneMobile;
	checkArray["email"] = email;
	checkArray["zip"] = zip;
	checkArray["arrl_expire"] = arrlDate;
	for (var index in checkArray){
		if (checkArray[index] == 'invalid')
		{
			var response = confirm("Phone#, email addr, zip or ARRL may be in error, continue anyway?");
			if (response) {
				//there's only on
				document.mbrVitals.submit();
			}else{
				//return
				return false;
			}
		}
	}
}

window.onload = function (){
	var elems = document.getElementsByClassName('confirm');
	var confirmIt = function (e) {
		if (!confirm('Are you sure?')) e.preventDefault();
	};
	for (var i = 0, l = elems.length; i < l; i++) {
		elems[i].addEventListener('click', confirmIt, false);
	}
	//************** VALIDATION ********************//
	function validatePassword(){
		var password = $("password"),
		confirm_password = $("confirm_password");
		var ok = true;
		if(password.value != confirm_password.value){
			confirm_password.setCustomValidity("Passwords don't match");
			ok = false;
		} else {
			confirm_password.setCustomValidity("");
		}
		return ok;
	}
	password.onchange = validatePassword();
	confirm_password.onkeyup = validatePassword;
	//*************** from w3 schools ***************//
	//https://www.w3schools.com/howto/howto_js_password_validation.asp
	var letter = $("letter");
	var capital = $("capital");
	var number = $("number");
	var length = $("length");

	// When the user clicks on the password field, show the message box
	password.onfocus = function() {
	  $("message").style.display = "block";
	}

	// When the user clicks outside of the password field, hide the message box
	password.onblur = function() {
	  $("message").style.display = "none";
	}

	// When the user starts to type something inside the password field
	password.onkeyup = function() {
	  // Validate lowercase letters
	  var lowerCaseLetters = /[a-z]/g;
	  if(password.value.match(lowerCaseLetters)) {
	    letter.classList.remove("invalid");
	    letter.classList.add("valid");
	  } else {
	    letter.classList.remove("valid");
	    letter.classList.add("invalid");
	  }

	  // Validate capital letters
	  var upperCaseLetters = /[A-Z]/g;
	  if(password.value.match(upperCaseLetters)) {
	    capital.classList.remove("invalid");
	    capital.classList.add("valid");
	  } else {
	    capital.classList.remove("valid");
	    capital.classList.add("invalid");
	  }

	  // Validate numbers
	  var numbers = /[0-9]/g;
	  if(password.value.match(numbers)) {
	    number.classList.remove("invalid");
	    number.classList.add("valid");
	  } else {
	    number.classList.remove("valid");
	    number.classList.add("invalid");
	  }

	  // Validate length
	  if(password.value.length >= 8) {
	    length.classList.remove("invalid");
	    length.classList.add("valid");
	  } else {
	    length.classList.remove("valid");
	    length.classList.add("invalid");
	  }
	}
	//*************** end w3 schools ****************//
}
