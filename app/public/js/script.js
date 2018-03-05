function $(id){
	return document.getElementById(id)
}
//************** ON CHANGE EVENTS ***************//
function queryType(){
	var x = $("query_select").value;
	$("demo").innerHTML = "you selected: " + x;
}
function arrlSet(){
	//make text editable and highlight textbox
	var arrl_expire = $("arrl_expire");
	if ($("arrl").checked){
		arrl_expire.disabled = "";
		arrl_expire.focus();
	}else{
		arrl_expire.disabled = "disabled";
		arrl_expire.value = "";
	}
		
}
//************** VALIDATION ********************//
function validateArrlExpDate(textbox){
	var date = textbox.value.trim();
	var datePattern = /^\d{4}-\d{2}-\d{2}$/
	if(!phone.match(phonePattern)){
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
		if (checkArray[index] == 'invalid' && $(index).value != '')
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