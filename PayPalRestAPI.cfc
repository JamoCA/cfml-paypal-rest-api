component name="PayPalRestAPI" hint="PayPal Rest API" {
	// 2024-10-14 v1 Supports auth and only very basic createOrder & orderCapture functions.

	variables.clientId = "";
	variables.clientSecret = "";
	variables.developmentmode = true;
	variables.descriptor = left(replacenocase(CGI.SERVER_NAME, "www.", ""), 22);

	public PayPalRestAPI function init(
			required string clientId
			,required string clientSecret
			,string developmentmode = ""
			,string descriptor = ""
		) output=false hint="I initialize the PayPal Rest API CFC" {
		variables.clientId = arguments.clientId;
		variables.clientSecret = arguments.clientSecret;
		if (len(arguments.developmentmode)) {
			if (!isvalid("boolean", arguments.developmentmode)){
				throw(message="PayPal Rest API: developmentmode flag must be boolean");
			}
			variables.developmentmode = arguments.developmentmode;
		}
		if (len(trim(arguments.descriptor))) {
			setDescriptor(arguments.descriptor);
		}
		return this;
	}

	public void function setDescriptor(required string descriptor) output=false hint="I set the Descriptor" {
		variables.descriptor = left(arguments.descriptor, 22);
	}
	public string function getDescriptor() output=false hint="I get the descriptor" {
		return variables.descriptor;
	}
	public string function getHost() hint="I return API host name" {
		return (variables.developmentmode) ? "https://api-m.sandbox.paypal.com" : "https://api-m.paypal.com";
	}

	public string function getAccessToken(
			string id=variables.clientId
			,string secret=variables.clientSecret
			,boolean forceRefresh = true
			,boolean debug = false
		) {
		local.cacheKey = "#CGI.SERVER_NAME#_PayPalRestAPI_TOKEN";
		local.token = cacheget(local.cacheKey);
		if (isnull(local.token) || arguments.forceRefresh){
			local.result = fetchAccessToken(id=arguments.id, secret=arguments.secret, debug=arguments.debug);
			if (local.result.keyexists("access_token") && len(local.result.access_token) gt 25){
				local.token = local.result.access_token;
				cacheput(local.cacheKey, local.token, createtimespan(0, 0, 0, local.result.expires_in-10));
			} else {
				cacheRemove(local.cacheKey);
				local.token = "";
			}
		}
		return local.token;
	}

	public struct function fetchAccessToken(string id=variables.clientId, string secret=variables.clientSecret, boolean debug=false) {
		cfhttp(method="post", charset="utf-8", url="#getHost()#/v1/oauth2/token", result="local.result", username=variables.clientid, password=variables.clientSecret, getasbinary="never", timeout=120) {
			cfhttpparam(type="header", name="Content_Type", value="application/x-www-form-urlencoded");
			cfhttpparam(name="grant_type", type="formfield", value="client_credentials");
		}
		if (arguments.debug){
			writedump(var=local.result, label="DEBUG: PayPalRestAPI fetchAccessToken", expand=false);
		}
		return (isjson(local.result.filecontent)) ? deserializejson(local.result.filecontent) : {"debug":duplicate(local.result)};
	}

	public struct function createOrder(
			string requestId = createuuid()
			,numeric amount = 0
			,string name = ""
			,string cardnumber = ""
			,string expdate = "" // yyyy-mm
			,string cvv2 = ""
			,string address = ""
			,string city = ""
			,string state = ""
			,string zip = ""
			,string country = "US"
			,string token = getAccessToken(forceRefresh=false)
		) hint="Creates an order." {

		arguments.cardnumber = 	javacast("string", arguments.cardnumber).replaceAll("\D", "");
		arguments.expdate = (isdate(arguments.expdate)) ? dateformat(arguments.expdate,'yyyy-mm') : trim(arguments.expdate);

		local.body = [
			"intent": "CAPTURE",
			"purchase_units": [
				[
					"reference_id": "default"
					// ,"description": ""
					// ,"custom_id": ""
					// ,"invoice_id": ""
					,"soft_descriptor": variables.descriptor
					,"amount": [
						"currency_code": "USD"
						,"value": "#trim(numberformat(arguments.amount, "99999999.00"))#"
					]
				]
			],
			"payment_source": [
				"card": [
					"name": trim(arguments.name)
					,"number": arguments.cardnumber
					,"security_code": trim(javacast("string", arguments.cvv2))
					,"expiry": arguments.expdate
					,"billing_address": [
						"address_line_1": trim(arguments.address)
						// ,"address_line_2": ""
						,"admin_area_2": trim(arguments.city)
						,"admin_area_1": trim(arguments.state)
						,"postal_code": trim(javacast("string", arguments.zip))
						,"country_code": trim(arguments.country)
					]
				]
			]
		];

		local.headers = [
			["name": "PayPal-Request-Id", "value": arguments.requestId],
			["name": "Authorization", "value": "Bearer #arguments.token#"]
		];

		local.data = doHttp(action="orders", headers=local.headers, body=local.body);

		return local.data;
	}

	public struct function captureOrder(
			required string id
			,required string requestId
			,string token = getAccessToken(forceRefresh=false)
		) hint="Captures payment for an order. Require" {
		local.headers = [
			["name": "PayPal-Request-Id", "value": arguments.requestId],
			["name": "Authorization", "value": "Bearer #arguments.token#"]
		];

		local.data = doHttp(action="orders/#trim(arguments.id)#/capture", headers=local.headers);

		return local.data;
	}

	private any function doHttp(string action, array headers=[], any body={}) output=true hint="I perform the HTTP request" {
		cfhttp(method="post", url="#getHost()#/v2/checkout/#arguments.action#", result="local.result", getasbinary="never", useragent="ColdFusion PayPalRestAPI", timeout=120, charset="utf-8") {
			cfhttpparam(type="header", name="Content_Type", value="application/json");
			for(local.header in arguments.headers){
				cfhttpparam(type="header", name=local.header.name, value=local.header.value);
			}
			if (issimplevalue(arguments.body)){
				cfhttpparam(type="body", value=arguments.body);
			} else if (isstruct(arguments.body) && structcount(arguments.body)){
				cfhttpparam(type="body", value=serializejson(arguments.body));
			}
		}
		writedump(var=arguments);
		writedump(var=local.result);
		local.data = (isjson(local.result.filecontent)) ? deserializejson(local.result.filecontent) : {"debug":duplicate(local.result)};
		local.data["id"] = local.data.keyexists("id") ? local.data.id : "";
		addResponseData(local.data);
		addErrorMessageData(local.data);
		return local.data;
	}

	private void function addResponseData(struct orderData) hint="Parse processor_response and inject keys" {
		arguments.orderData["responseCode"] = "9600";
		arguments.orderData["responseCodeText"] = "UNRECOGNIZED_RESPONSE_CODE";
		arguments.orderData["responseCodeMessage"] = "Unrecognized response code.";
		arguments.orderData["avsMessage"] = "";
		arguments.orderData["cvvMessage"] = "";
		arguments.orderData["transactionId"] = "";
		arguments.orderData["paypalId"] = "";
		arguments.orderData["status"] = "";
		arguments.orderData["network"] = "";

		local.data = {};
		// createOrder/capture - check for a single arguments.orderdata.purchase_units[1].paments.captures[1] struct
		if (isdefined("arguments.orderdata.purchase_units") && isarray(arguments.orderdata.purchase_units) && arraylen(arguments.orderdata.purchase_units) eq 1 && arguments.orderdata.purchase_units[1].keyexists("payments") && arguments.orderdata.purchase_units[1].payments.keyexists("captures") && isarray(arguments.orderdata.purchase_units[1].payments.captures) && arraylen(arguments.orderdata.purchase_units[1].payments.captures) eq 1){
			local.data = arguments.orderdata.purchase_units[1].payments.captures[1];
		}
		if (local.data.keyexists("processor_response")){
			if (local.data.processor_response.keyexists("response_code")){
				arguments.orderData["responseCode"] = javacast("string", local.data.processor_response.response_code);
				arguments.orderData["responseCodeText"] = listfirst(getResponseMessage(local.data.processor_response.response_code), ".");
				arguments.orderData["responseCodeMessage"] = toSentenceCase(replace(getResponseMessage(local.data.processor_response.response_code), "_", " ", "all"));
			}
			if (local.data.processor_response.keyexists("avs_code")){
				arguments.orderData["avsMessage"] = getAVSMessage(local.data.processor_response.avs_code);
			}
			if (local.data.processor_response.keyexists("cvv_code")){
				arguments.orderData["cvvMessage"] = getCVVMessage(local.data.processor_response.cvv_code);
			}
		}
		if (isdefined("local.data.network_transaction_reference.id")){
			arguments.orderData["transactionId"] = local.data.network_transaction_reference.id;
		}
		if (isdefined("local.data.id")){
			arguments.orderData["paypalId"] = local.data.id;
		}
		if (isdefined("local.data.network_transaction_reference.network")){
			arguments.orderData["network"] = local.data.network_transaction_reference.network;
		}
		if (isdefined("local.data.status")){
			arguments.orderData["status"] = local.data.status;
		}
	}

	private void function addErrorMessageData(struct orderData) {
		local.errorMessage = getErrorMessage(arguments.orderData);
		arguments.orderData["errorMessage"] = local.errorMessage;
	}

	public string function getErrorMessage(struct orderData) {
		local.msg = [];
		if (arguments.orderData.keyexists("error_description")){
			arrayappend(local.msg, arguments.orderData.error_description.toString());
		}
		if (arguments.orderData.keyexists("ERRORMESSAGE")){
			arrayappend(local.msg, arguments.orderData.ERRORMESSAGE.toString());
		}
		if (arguments.orderData.keyexists("message")){
			arrayappend(local.msg, arguments.orderData.message.toString());
		}
		if (arguments.orderData.keyexists("details") && isarray(arguments.orderData.details) && arraylen(arguments.orderData.details)){
			for (local.detail in arguments.orderData.details){
				if (local.detail.keyexists("description")){
					arrayappend(local.msg, local.detail.description);
				}
			}
		}
		if (!arraylen(local.msg) && isdefined("arguments.orderData.responseCode") && len(arguments.orderData.responseCode) && arguments.orderData.responseCode neq "0000"){
			arrayappend(local.msg, arguments.orderData.responseCodeMessage);
		}
		return (arraylen(local.msg)) ? arraytolist(local.msg, "; ") : "";
	}

	public string function toSentenceCase(string text) hint="I capitalize the first letter of first word in a every sentence" {
		local.text = lcase(javacast("string", arguments.text));
		// local.matches = rematch('\w.+?[.?!]+', local.text);
		local.matches = rematch("\w.+?[.?!]+|\w.+$", local.text);
		local.text = "";
		for (local.i in local.matches) {
			local.text &= replacenocase(local.i, left(local.i, 1), ucase(left(local.i, 1))) & " ";
		}
		return local.text;
	}

	public any function getAVSMessage(required string code, string cardBrand="") hint="Enums for the address verification code for Visa, Discover, Mastercard, or American Express transactions." {
		local.data = [
			"0": "All address information matches."
			,"1": "None of the address information matches."
			,"2": "Part of the address information matches."
			,"3": "The merchant did not provide AVS information. It was not processed."
			,"4": "The address was not checked or the acquirer had no response. The service is not available."
			,"A": "The address matches but the zip code does not match."
			,"A_AMEX": "The card holder address is correct."
			,"B": "The address matches. International A."
			,"C": "No values match. International N."
			,"D": "The address and postal code match. International X."
			,"E": "Not allowed for Internet or phone transactions."
			,"E_AMEX": "The name is incorrect but the address and postal code match."
			,"F": "The address and postal code match. UK-specific X."
			,"F_AMEX": "The name is incorrect but the address matches."
			,"G": "Global is unavailable. Nothing matches."
			,"I": "Iinternational is unavailable. Not applicable."
			,"M": "The address and postal code match."
			,"M_AMEX": "The name, address, and postal code match."
			,"N": "Nothing matches."
			,"N_AMEX": "The address and postal code are both incorrect."
			,"P": "Postal international Z. Postal code only."
			,"R": "Re-try the request."
			,"R_AMEX": "The system is unavailable."
			,"S": "The service is not supported."
			,"U": "The service is unavailable."
			,"U_AMEX": "Information is not available."
			,"U_MAESTRO": "The address is not checked or the acquirer had no response. The service is not available."
			,"W": "Whole ZIP code. For American Express, the card holder name, address, and postal code are all incorrect."
			,"W_AMEX": "The card holder name, address, and postal code are all incorrect."
			,"X": "Exact match of the address and the nine-digit ZIP code."
			,"X_AMEX": "The card holder name, address, and postal code are all incorrect."
			,"Y": "The address and five-digit ZIP code match."
			,"Y_AMEX": "The card holder address and postal code are both correct."
			,"Z": "The five-digit ZIP code matches but no address."
			,"Z_AMEX": "Only the card holder postal code is correct."
		];
		if (arguments.code eq "all"){
			return local.data;
		} else if (structkeyexists(local.data, arguments.code & "_" & arguments.cardBrand)){
			return local.data[arguments.code & "_" & arguments.cardBrand];
		} else if (structkeyexists(local.data, arguments.code)){
			return local.data[arguments.code];
		}
		return "No AVS response was obtained.";
	}

	public any function getCVVMessage(required string code) hint="Enums for the card verification value code for for Visa, Discover, Mastercard, or American Express." {
		local.data = [
			"0": "The CVV2 matched."
			,"1": "The CVV2 did not match."
			,"2": "The merchant has not implemented CVV2 code handling."
			,"3": "The merchant has indicated that CVV2 is not present on card."
			,"4": "The service is not available."
			,"E": "Error - unrecognized or unknown response."
			,"I": "Invalid or null."
			,"M": "The CVV2/CSC matches."
			,"N": "The CVV2/CSC does not match."
			,"P": "It was not processed."
			,"S": "The service is not supported."
			,"U": "Unknown - the issuer is not certified."
			,"X": "No response. For Maestro, the service is not available."
		];
		if (arguments.code eq "all"){
			return local.data;
		} else if (structkeyexists(local.data, arguments.code)){
			return local.data[arguments.code];
		}
		return "error.";
	}

	public any function getResponseMessage(required string code) hint="Enums for Processor response code for the non-PayPal payment processor errors." {
		local.data = [
			"0000": "APPROVED."
			,"00N7": "CVV2_FAILURE_POSSIBLE_RETRY_WITH_CVV."
			,"0100": "REFERRAL."
			,"0390": "ACCOUNT_NOT_FOUND."
			,"0500": "DO_NOT_HONOR."
			,"0580": "UNAUTHORIZED_TRANSACTION."
			,"0800": "BAD_RESPONSE_REVERSAL_REQUIRED."
			,"0880": "CRYPTOGRAPHIC_FAILURE."
			,"0890": "UNACCEPTABLE_PIN."
			,"0960": "SYSTEM_MALFUNCTION."
			,"0R00": "CANCELLED_PAYMENT."
			,"1000": "PARTIAL_AUTHORIZATION."
			,"10BR": "ISSUER_REJECTED."
			,"1300": "INVALID_DATA_FORMAT."
			,"1310": "INVALID_AMOUNT."
			,"1312": "INVALID_TRANSACTION_CARD_ISSUER_ACQUIRER."
			,"1317": "INVALID_CAPTURE_DATE."
			,"1320": "INVALID_CURRENCY_CODE."
			,"1330": "INVALID_ACCOUNT."
			,"1335": "INVALID_ACCOUNT_RECURRING."
			,"1340": "INVALID_TERMINAL."
			,"1350": "INVALID_MERCHANT."
			,"1352": "RESTRICTED_OR_INACTIVE_ACCOUNT."
			,"1360": "BAD_PROCESSING_CODE."
			,"1370": "INVALID_MCC."
			,"1380": "INVALID_EXPIRATION."
			,"1382": "INVALID_CARD_VERIFICATION_VALUE."
			,"1384": "INVALID_LIFE_CYCLE_OF_TRANSACTION."
			,"1390": "INVALID_ORDER."
			,"1393": "TRANSACTION_CANNOT_BE_COMPLETED."
			,"5100": "GENERIC_DECLINE."
			,"5110": "CVV2_FAILURE."
			,"5120": "INSUFFICIENT_FUNDS."
			,"5130": "INVALID_PIN."
			,"5135": "DECLINED_PIN_TRY_EXCEEDED."
			,"5140": "CARD_CLOSED."
			,"5150": "PICKUP_CARD_SPECIAL_CONDITIONS. Try using another card. Do not retry the same card."
			,"5160": "UNAUTHORIZED_USER."
			,"5170": "AVS_FAILURE."
			,"5180": "INVALID_OR_RESTRICTED_CARD. Try using another card. Do not retry the same card."
			,"5190": "SOFT_AVS."
			,"5200": "DUPLICATE_TRANSACTION."
			,"5210": "INVALID_TRANSACTION."
			,"5400": "EXPIRED_CARD."
			,"5500": "INCORRECT_PIN_REENTER."
			,"5650": "DECLINED_SCA_REQUIRED."
			,"5700": "TRANSACTION_NOT_PERMITTED. Outside of scope of accepted business."
			,"5710": "TX_ATTEMPTS_EXCEED_LIMIT."
			,"5800": "REVERSAL_REJECTED."
			,"5900": "INVALID_ISSUE."
			,"5910": "ISSUER_NOT_AVAILABLE_NOT_RETRIABLE."
			,"5920": "ISSUER_NOT_AVAILABLE_RETRIABLE."
			,"5930": "CARD_NOT_ACTIVATED."
			,"5950": "DECLINED_DUE_TO_UPDATED_ACCOUNT. External decline as an updated card has been issued."
			,"6300": "ACCOUNT_NOT_ON_FILE."
			,"7600": "APPROVED_NON_CAPTURE."
			,"7700": "ERROR_3DS."
			,"7710": "AUTHENTICATION_FAILED."
			,"7800": "BIN_ERROR."
			,"7900": "PIN_ERROR."
			,"8000": "PROCESSOR_SYSTEM_ERROR."
			,"8010": "HOST_KEY_ERROR."
			,"8020": "CONFIGURATION_ERROR."
			,"8030": "UNSUPPORTED_OPERATION."
			,"8100": "FATAL_COMMUNICATION_ERROR."
			,"8110": "RETRIABLE_COMMUNICATION_ERROR."
			,"8220": "SYSTEM_UNAVAILABLE."
			,"9100": "DECLINED_PLEASE_RETRY. Retry."
			,"9500": "SUSPECTED_FRAUD. Try using another card. Do not retry the same card."
			,"9510": "SECURITY_VIOLATION."
			,"9520": "LOST_OR_STOLEN. Try using another card. Do not retry the same card."
			,"9530": "HOLD_CALL_CENTER. The merchant must call the number on the back of the card. POS scenario."
			,"9540": "REFUSED_CARD."
			,"9600": "UNRECOGNIZED_RESPONSE_CODE."
			,"PCNR": "CONTINGENCIES_NOT_RESOLVED."
			,"PCVV": "CVV_FAILURE."
			,"PP06": "ACCOUNT_CLOSED. A previously open account is now closed"
			,"PPAB": "ACCOUNT_BLOCKED_BY_ISSUER."
			,"PPAD": "BILLING_ADDRESS."
			,"PPAE": "AMEX_DISABLED."
			,"PPAG": "ADULT_GAMING_UNSUPPORTED."
			,"PPAI": "AMOUNT_INCOMPATIBLE."
			,"PPAR": "AUTH_RESULT."
			,"PPAU": "MCC_CODE."
			,"PPAV": "ARC_AVS."
			,"PPAX": "AMOUNT_EXCEEDED."
			,"PPBG": "BAD_GAMING."
			,"PPC2": "ARC_CVV."
			,"PPCE": "CE_REGISTRATION_INCOMPLETE."
			,"PPCO": "COUNTRY."
			,"PPCR": "CREDIT_ERROR."
			,"PPCT": "CARD_TYPE_UNSUPPORTED."
			,"PPCU": "CURRENCY_USED_INVALID."
			,"PPD3": "SECURE_ERROR_3DS."
			,"PPDC": "DCC_UNSUPPORTED."
			,"PPDI": "DINERS_REJECT."
			,"PPDT": "DECLINE_THRESHOLD_BREACH."
			,"PPDV": "AUTH_MESSAGE."
			,"PPEF": "EXPIRED_FUNDING_INSTRUMENT."
			,"PPEL": "EXCEEDS_FREQUENCY_LIMIT."
			,"PPER": "INTERNAL_SYSTEM_ERROR."
			,"PPEX": "EXPIRY_DATE."
			,"PPFE": "FUNDING_SOURCE_ALREADY_EXISTS."
			,"PPFI": "INVALID_FUNDING_INSTRUMENT."
			,"PPFR": "RESTRICTED_FUNDING_INSTRUMENT."
			,"PPFV": "FIELD_VALIDATION_FAILED."
			,"PPGR": "GAMING_REFUND_ERROR."
			,"PPH1": "H1_ERROR."
			,"PPIF": "IDEMPOTENCY_FAILURE."
			,"PPII": "INVALID_INPUT_FAILURE."
			,"PPIM": "ID_MISMATCH."
			,"PPIT": "INVALID_TRACE_ID."
			,"PPLR": "LATE_REVERSAL."
			,"PPLS": "LARGE_STATUS_CODE."
			,"PPMB": "MISSING_BUSINESS_RULE_OR_DATA."
			,"PPMC": "BLOCKED_Mastercard."
			,"PPMD": "PPMD."
			,"PPNC": "NOT_SUPPORTED_NRC."
			,"PPNL": "EXCEEDS_NETWORK_FREQUENCY_LIMIT."
			,"PPNM": "NO_MID_FOUND."
			,"PPNT": "NETWORK_ERROR."
			,"PPPH": "NO_PHONE_FOR_DCC_TRANSACTION."
			,"PPPI": "INVALID_PRODUCT."
			,"PPPM": "INVALID_PAYMENT_METHOD."
			,"PPQC": "QUASI_CASH_UNSUPPORTED."
			,"PPRE": "UNSUPPORT_REFUND_ON_PENDING_BC."
			,"PPRF": "INVALID_PARENT_TRANSACTION_STATUS."
			,"PPRN": "REATTEMPT_NOT_PERMITTED."
			,"PPRR": "MERCHANT_NOT_REGISTERED."
			,"PPS0": "BANKAUTH_ROW_MISMATCH."
			,"PPS1": "BANKAUTH_ROW_SETTLED."
			,"PPS2": "BANKAUTH_ROW_VOIDED."
			,"PPS3": "BANKAUTH_EXPIRED."
			,"PPS4": "CURRENCY_MISMATCH."
			,"PPS5": "CREDITCARD_MISMATCH."
			,"PPS6": "AMOUNT_MISMATCH."
			,"PPSC": "ARC_SCORE."
			,"PPSD": "STATUS_DESCRIPTION."
			,"PPSE": "AMEX_DENIED."
			,"PPTE": "VERIFICATION_TOKEN_EXPIRED."
			,"PPTF": "INVALID_TRACE_REFERENCE."
			,"PPTI": "INVALID_TRANSACTION_ID."
			,"PPTR": "VERIFICATION_TOKEN_REVOKED."
			,"PPTT": "TRANSACTION_TYPE_UNSUPPORTED."
			,"PPTV": "INVALID_VERIFICATION_TOKEN."
			,"PPUA": "USER_NOT_AUTHORIZED."
			,"PPUC": "CURRENCY_CODE_UNSUPPORTED."
			,"PPUE": "UNSUPPORT_ENTITY."
			,"PPUI": "UNSUPPORT_INSTALLMENT."
			,"PPUP": "UNSUPPORT_POS_FLAG."
			,"PPUR": "UNSUPPORTED_REVERSAL."
			,"PPVC": "VALIDATE_CURRENCY."
			,"PPVE": "VALIDATION_ERROR."
			,"PPVT": "VIRTUAL_TERMINAL_UNSUPPORTED."
		];
		if (arguments.code eq "all"){
			return local.data;
		} else if (structkeyexists(local.data, arguments.code)){
			return local.data[arguments.code];
		}
		return "Unknown";
	}

	public any function getPaymentAdviceMessage(required string code, string cardBrand="") hint="Enums for the declined payment transactions might have payment advice codes. The card networks, like Visa and Mastercard, return payment advice codes." {
		local.data = [
			"21": "Recurring payments have been canceled for the card number requested. Stop recurring payment requests."
			,"21_MAESTRO": "The card holder has been unsuccessful at canceling recurring payment through merchant. Stop recurring payment requests."
			,"21_VISA": "All recurring payments were canceled for the card number requested. Stop recurring payment requests."
			,"01": "Expired card account upgrade or portfolio sale conversion. Obtain new account information before next billing cycle."
			,"02": "Retry the transaction 72 hours later."
			,"02_MASTERCARD": "Over credit limit or insufficient funds. Retry the transaction 72 hours later."
			,"02_VISA": "The card holder wants to stop only one specific payment in the recurring payment relationship. The merchant must NOT resubmit the same transaction. The merchant can continue the billing process in the subsequent billing period."
			,"03": "Account closed as fraudulent or card holder wants to stop all recurring payment transactions. Stop recurring payment requests."
			,"03_MASTERCARD": "Account closed as fraudulent. Obtain another type of payment from customer due to account being closed or fraud. Possible reason: Account closed as fraudulent."
			,"03_VISA": "The card holder wants to stop all recurring payment transactions for a specific merchant. Stop recurring payment requests."
		];
		if (arguments.code eq "all"){
			return local.data;
		} else if (structkeyexists(local.data, arguments.code & "_" & arguments.cardBrand)){
			return local.data[arguments.code & "_" & arguments.cardBrand];
		} else if (structkeyexists(local.data, arguments.code)){
			return local.data[arguments.code];
		}
		return "error.";
	}


	public any function getBrandName(required string code) hint="The card brand or network. Typically used in the response." {
		local.data = [
			"VISA": "Visa card"
			,"MASTERCARD": "Mastecard card"
			,"DISCOVER": "Discover card"
			,"AMEX": "American Express card"
			,"SOLO": "Solo debit card"
			,"JCB": "Japan Credit Bureau card"
			,"STAR": "Military Star card"
			,"DELTA": "Delta Airlines card"
			,"SWITCH": "Switch credit card"
			,"MAESTRO": "Maestro credit card"
			,"CB_NATIONALE": "Carte Bancaire (CB) credit card"
			,"CONFIGOGA": "Configoga credit card"
			,"CONFIDIS": "Confidis credit card"
			,"ELECTRON": "Visa Electron credit card"
			,"CETELEM": "Cetelem credit card"
			,"CHINA_UNION_PAY": "China union pay credit card"
			,"DINERS": "The Diners Club International banking and payment services capability network owned by Discover Financial Services (DFS), one of the most recognized brands in US financial services"
			,"ELO": "The Brazilian Elo card payment network"
			,"HIPER": "The Hiper - Ingenico ePayment network"
			,"HIPERCARD": "The Brazilian Hipercard payment network that's widely accepted in the retail market"
			,"RUPAY": "The RuPay payment network"
			,"GE": "The GE Credit Union 3Point card payment network"
			,"SYNCHRONY": "The Synchrony Financial (SYF) payment network"
			,"EFTPOS": "The Electronic Fund Transfer At Point of Sale(EFTPOS) Debit card payment network"
			,"UNKNOWN": "UNKNOWN payment network"
		];
		if (arguments.code eq "all"){
			return local.data;
		} else if (structkeyexists(local.data, arguments.code)){
			return local.data[arguments.code];
		}
		return "error.";
	}

}

