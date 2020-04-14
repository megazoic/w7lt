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
function duesSet(selectElement){
	//set visibility of elements in m_renew.rb related to dues/non-dues payment
	//get the payment_type inner text
	var seText = selectElement.options[selectElement.selectedIndex].text;
	if (seText == 'Dues'){
		$("message").style.display = "block";
	}else{
		$("message").style.display = "none";
	}
}
function authUserStatusSet(inputElement){
	//set visibility of authorized user roles based on their status
	var ieValue = inputElement.value;
	if (ieValue == "1") {
		$("roles").style.display = "block";
	} else {
		$("roles").style.display = "none";
	}
}
//**************VALIDATORS*****************************
function validatePayAmt(textbox){
	var tb = textbox.value.trim();
	var amtPattern = /^\d{1,}(\.\d{1,2})?$/
	if(!tb.match(amtPattern) && tb != ''){
		textbox.style.borderColor = 'red';
		textbox.setAttribute('isInValid','invalid');
	}else{
		textbox.style.borderColor = 'black';
		textbox.setAttribute('isInValid','');
	}
}
function validateFirstName(textbox){
	var tb = textbox.value;
	if (tb == ''){
		textbox.style.borderColor = 'red';
		textbox.setAttribute('isInValid','invalid');
	} else {
		textbox.style.borderColor = 'black';
		textbox.setAttribute('isInValid','');
	}
}
function validateLastName(textbox){
	var tb = textbox.value;
	if (tb == ''){
		textbox.style.borderColor = 'red';
		textbox.setAttribute('isInValid','invalid');
	} else {
		textbox.style.borderColor = 'black';
		textbox.setAttribute('isInValid','');
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
function validateMbrSince(textbox){
	var mbr_since = textbox.value.trim();
	//date pattern YYYY-MM
	var mbr_sincePattern = /^[12]\d{3,3}-(1[0-2]|0[1-9])$/;
	if (mbr_sincePattern.test(mbr_since)){
		//test for date < today && date > club formed
		var mon = mbr_since.substr(5,2);
		var yr = mbr_since.substr(0,4);
		var m = parseInt(mon) - 1; //JS is 0 based month
		var y = parseInt(yr);
		var enteredDate = new Date(y,m);
		var today = new Date();
		var parcFormed = new Date(1941, 0);
		var acceptableDate = today - parcFormed;
		var dateToTest = enteredDate - parcFormed;
		if (dateToTest > 0 && dateToTest < acceptableDate){
			//we're good
			textbox.style.borderColor = 'black';
			textbox.setAttribute('isInValid','');
			return 0;
		}
	}
	textbox.style.borderColor = 'red';
	textbox.setAttribute('isInValid','invalid');
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
		//document.auRoles.submit();
		return true;
	} else {
		//could be status was inactive when loaded
		var au_status = $("inactive").checked
		if (au_status == true){
			//ok, allow submission of form
			return true;
		}
		alert("At least one Role must be selected");
		return false;
	}
}
function validateMbrPayForm(){
	var paid_up = $("paid_yr_field").value;
	var mbr_type = $("mbr_type").value;
	var pay_amt = $("payment_amt_field");
	var pay_mthd = $("payment_method_field");
	var pmText = pay_mthd.options[pay_mthd.selectedIndex].text
	var pay_type = $("payment_type_field");
	var ptText = pay_type.options[pay_type.selectedIndex].text;
	//cannot submit if payment field is invalid
	if (pay_amt.getAttribute('isInValid') == 'invalid' || pay_amt.value == ''){
		alert("Enter a number in the amount field");
		return false;
	}
	//cannot submit if payment type, methods are not selected
	if (pay_mthd.value == '' || pay_type.value == ''){
		alert("You must select a payment type and method");
		return false;
	}
	//need to taylor the confirm to dues/non-dues payments
	if (ptText == 'Dues'){
		yes = confirm("Is this correct?\n\n" + "Member type: " + mbr_type + "\nPaid through: " + paid_up);
	}else{
		yes = confirm("Is this correct?\n\n" + "Payment type: " + ptText + "\nMethod: " + pmText + "\nAmount: " + pay_amt.value);
	}
	if (yes){
		return true;
	}else{
		return false;
	}
}
function validateMbrForm(){
	//first handle must haves
	var firstName = $("fname").getAttribute('isInValid');
	var lastName = $("lname").getAttribute('isInValid');
	var mbr_since = $("mbr_since").getAttribute('isInValid');
	if (firstName == 'invalid' || lastName == 'invalid' || mbr_since == 'invalid'){
		alert("Please be sure to include a first and\nlast name as well as proper date format\nbefore submitting this form")
		return false;
	}
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
function validateUnitEditForm(){
	//need to make sure >1 mbr in a unit;
	//if unit is elmer, 1 or more mbrs; no elmers selected (already have one)
	var checkedBoxes = document.querySelectorAll("input[name*=\'id:\']:checked");
	var is_elmer_unit = $('elmer').value;
	var have_elmer = "N";
	var mbrs = checkedBoxes.length;
	if (is_elmer_unit == "1"){
		for (var i = 0; i < checkedBoxes.length; i++){
			var m = checkedBoxes[i].name.match(/\d+:([NY])/);
			if (m[1] == "Y") have_elmer = "Y";
		}
		if (mbrs > 0){
			if (have_elmer == "Y"){
				alert("you have 2 elmers. if you need to change elmers, create new unit");
				return false;
			}//else Ok to submit form
		} else {
			alert("you need to have one non-elmer member of this unit");
			return false;
		}
	}
	else if (mbrs < 2){
		alert("you need at least 2 members in a unit");
		return false;
	}
	return true;
}
function validateUnitNewForm(){
	//unit type needs to be selected
	//need to make sure > 1 mbr in a unit; 1 and only elmer in unit elmer
	var checkedBoxes = document.querySelectorAll("input[name*=\'id:\']:checked");
	var is_elmer_unit = document.getElementById('unit_type').value;
	if (is_elmer_unit == 'none') {
		alert("please select unit type");
		return false;
	}
	var have_elmer = 0;
	var mbrs = checkedBoxes.length;
	if (is_elmer_unit == "elmer"){
		for (var i = 0; i < checkedBoxes.length; i++){
			var m = checkedBoxes[i].name.match(/\d+:([NY])/);
			if (m[1] == "Y") have_elmer = have_elmer + 1;
		}
		if (mbrs > 1){
			if (have_elmer > 1 || have_elmer == 0){
				alert("too many elmers, please choose one and only one elmer");
				return false;
			}//else Ok to submit form
		} else {
			alert("you need at least 2 members in this unit");
			return false;
		}
	}
	else if (mbrs < 2){
		//alert("you need at least 2 members in a unit");
		var response = confirm("Proceed with only one member in this unit?")
		if (response){
			return true;
		} else {
			return false;
		}
	}
	return true;
}
function validateUnitTypeForm(){
	//don't want type field empty and cannot have same type as existing unit type
	var old_type_names = $('old_type_names').value;
	var new_type_name = $('new_type_name').value;
	var edit_old_type = $('editing_old_type').value;
	console.log("e o t is " + edit_old_type);
	if (new_type_name == ''){
		alert("please give this unit type a name");
		return false;
	}
	if (edit_old_type == '0'){
		var old_type_names_array = old_type_names.split(",");
		//from script in create_unit_type.erb
		for (var i = 0; i < old_type_names_array.length; i++){
			if (old_type_names_array[i] == new_type_name){
				alert("there is already a unit type with this name, please use that one");
				return false;
			}
		}
	}
	return true;
}

window.onload = function (){
	//load only if using password reset page
	if (document.body.id == "PwdReset"){
		//************** VALIDATION ********************//
		var password = $("password"),
		confirm_password = $("confirm_password");
		function validatePassword(){
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

		//When the user clicks on the password field, show the message box
		password.onfocus = function() {
		  $("message").style.display = "block";
		}

		//When the user clicks outside of the password field, hide the message box
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
}
