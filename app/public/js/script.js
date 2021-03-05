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
function other_pmtSet(){
	//enable textbox for other payment amount
	$("other_pmt_field").disabled = false;
}
function guestsSet(inputElement){
	//set visibility of new guests table in e_create.erb
	if (inputElement.checked){
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
	var paid_up = $("paid_up_field").value;
	//var mbr_type = $("mbr_type").value;
	var pay_mthd = $("payment_method_field");
	var pmText = pay_mthd.options[pay_mthd.selectedIndex].text;
	var pay_type = $("payment_type_field");
	var ptText = pay_type.options[pay_type.selectedIndex].text;
	//test if have two payment amounts (radio and other)
	var other_pay = $("other_pmt").checked;
	var other_pay_amt = $("other_pmt_field").value;
	//var pay_amt_selected = $("mbr_type").value;
	//var pay_amt = $("mbr_type").value;
	var pay_amt = "";
	var pay_amt_name = "";
        var x = document.getElementById("mbr_type");
        for (var i = 0; i < x.length; i++){
        	if (x[i].selected){
      	  		//pay_amt_selected = true;
			pay_amt_name = x[i].value;
			var pattern = /pay_(.*)/;
			const match = x[i].id.match(pattern);
			pay_amt = match[1];
          	}
        }
	//use regexp to compare member type with payment amount
	//shouldn't have a member type of 'full; but payment 'family'
	/*
	// if pay_amt_id == "pay_amt_full" for example
	var pattern = /pay_amt_(.*)/;
	const match = pay_amt_id.match(pattern);
	// match[1] should be 'full'
	
	*/
        var other_pay_amt = document.getElementById("other_pmt_field").value;
	//const date_now = new Date().getFullYear();
	//const pay_amt = (paid_up - date_now) * payFees[mbr_type];
	//cannot submit if payment field is invalid
	/*if (pay_amt.getAttribute('isInValid') == 'invalid' || pay_amt.value == ''){
		alert("Enter a number in the amount field");
		return false;
	}*/
	//cannot submit if payment type, methods are not selected
	if (pay_mthd.value == '' || pay_type.value == ''){
		alert("You must select a payment type and method");
		return false;
	}
	//need to taylor the confirm to dues/non-dues payments
	if (ptText == 'Dues'){
		//test to see if payment amount radio button or other payment amount is selected
		//not both
	        if (other_pay == true && other_pay_amt != ""){
			if (isNaN(other_pay_amt)){
				alert("other payment amount must be a number");
				return false;
			}
			if ($("notes_field").value == ""){
				alert("must place note why using other payment");
				return false;
			}
			yes = confirm("Is this correct?\n\n" + "Member type: " + pay_amt_name + "\nPaid through: " + paid_up +
			"\nPay Amount: $" + other_pay_amt + "\nPayment Method: " + pmText);
	        }else if (other_pay == false && other_pay_amt == ""){
			//test to see if member type and payment amount match
			/*if (pay_amt_name != mbr_type){
				alert("member type and payment amount need to match");
				return false;
			}*/
			yes = confirm("Is this correct?\n\n" + "Member type: " + pay_amt_name + "\nPaid through: " + paid_up +
			"\nPay Amount: $" + pay_amt + "\nPayment Method: " + pmText);
	        }else{
	        	alert("If choose other memeber type, must fill out amount");
			return false;
	        }
	}else{
		yes = confirm("Is this correct?\n\n" + "Payment type: " + ptText + "\nMethod: " + pmText + "\nAmount: " + pay_amt);
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
function validatePayDestroy(){
	//need to ok this action
	console.log ("in pay destroy");
	var agree = confirm("Are you sure you want to delete this payment record?");
	var confirmIt = $("confirmIt");
	if (agree){
		confirmIt.value = "Yes";
	}
	return true
}
function validateCreateEventForm(){
	//need to have a member contact, event type
	var event_type = $('type').value;
	if (event_type == "none"){
		alert("please select an event type");
		return false;
	}
	var mbr_selected = false;
        var chx = document.getElementsByName('mbr_id');
        for (var i = 0; i < chx.length; i++) {
		if (chx[i].checked) {
            mbr_selected = true;
          }
        }
	if (mbr_selected == false){
		alert("please select an event contact");
		return false;
	}
	//need to validate guest emails
	//default is '*guest email' which should be allowed
	var g_emails = document.getElementsByClassName('guestEmail');
	//a close approximation
	var emailPattern = /^\w[-.\w]*@[-a-z0-9]+(\.[-a-z0-9]+)*\.(com|edu|info|mil|net|org|biz|[a-z][a-z])$/i;
	for(var i = 0; i < g_emails.length; i++){
		var email = g_emails[i].value
		if (!email.match(emailPattern) && email != '*guest email'){
			var agree = confirm("A guest email may be incorrect, proceed anyway?");
			if (agree != true){
				return false;
			}
		}
	}
	//validate datetime as YYYY-MM-DD HH:MM
	var event_date = $('event_date').value;
	if (!event_date.match(/202\d-[01]\d-[0-3]\d\s+[012]\d:[0-5]\d/)){
		alert("date doesn't match expected format");
		return false;
	}
	//validate that if a duration is chosen, a duration_units is also picked
	var duration = $('duration').value;
	var duration_unit_hrs = $('durat_hrs').checked;
	var duration_unit_days = $('durat_days').checked;
	if (duration != "none" && (duration_unit_hrs == false && duration_unit_days == false)){
		alert("if a duration for this event is selected, a unit must also be chosen");
		return false;
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
