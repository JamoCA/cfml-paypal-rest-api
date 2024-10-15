<cfscript>

// Paypal REST API Documentation https://developer.paypal.com/api/rest/

payPalApi = new PaypalRestAPI(
	clientId = "FAKE-4dd52b89-d651-445e-82d4-9eec3629ffbb"
	,clientSecret = "FAKE-5a5a6a0b-5237-41a8-82b9-7d7fc9f671ed"
	,descriptor = "My Big Business Name" // <= 22 chars
	,developmentMode = true
);

// writedump(var=payPalApi, label="Public PaypalRestAPI methods");

// authentication logic
payPalToken = payPalApi.getAccessToken(forceRefresh=1, debug=true);
writedump(var=payPalToken, label="payPalToken");
// abort;

// REQUIRED: create unique ID for tracking order
requestId = createuuid();

// create order  (address & CVV2 are required)
orderData = [
	"requestId": requestId
	,"amount": 14.99
];
writedump(var=orderData, label="orderData");

order = payPalApi.createOrder(argumentcollection=orderData);

isCreated = len(order.id) && order.status eq "created";

if (isCreated){
	writeoutput("<p><b>Success:</b> Pending Order ID: #order.id#</p>");
} else {
	writeoutput("<p style=""color:red;""><b>Order Error:</b> #order.errorMessage#</p>");
}
writedump(var=order, label="createOrder response");

// return to edit the CC info
if (!isCreated){
	writeoutput("<p>Creation failed. Redisplay form to allow corrections...</p>");
	exit;
}

/*	Pay Pal Development Mode

	Test CC: 4556747948786484

	Add keywords to the cardholder name to perform tests.
	https://developer.paypal.com/api/rest/sandbox/card-testing/
	CCREJECT-REFUSED: Card refused
	CCREJECT-SF: Fraudulent card
	CCREJECT-EC: Card expired
	CCREJECT-IRC: Luhn Check fails
	CCREJECT-IF: Insufficient funds
	CCREJECT-LS: Card lost, stolen
	CCREJECT-IA: Card not valid
	CCREJECT-BANK_ERROR: Card is declined
	CCREJECT-CVV_F: CVC check fails
*/

// capture order
orderDataToCapture = [
	"requestId": requestId
	,"id": order.id
	,"name": "Joe Cardholder"
	,"cardnumber": "4556747948786484"
	,"expdate": dateadd("m", 2, now()) // format "yyyy-mm" or pass a date object
	,"cvv2": "789"
	,"address": "123 ABC Street" // optional
	,"city": "Anytown" // optional (admin_area_2)
	,"state": "CA" // optional  (admin_area_1)
	,"zip": "90210" // optional (postal_code)
	,"country": "US" // optional
];
writedump(var=orderDataToCapture, label="orderDataToCapture");

capturedOrder = payPalApi.captureOrder(argumentcollection=orderDataToCapture);

isCaptured = len(capturedOrder.transactionId) && capturedOrder.status eq "completed";

if (isCaptured){
	writeoutput("<p><b>Success:</b> TransactionID: #capturedOrder.transactionId#</p>");
} else {
	writeoutput("<p style=""color:red;""><b>Capture Error:</b> #capturedOrder.errorMessage#</p>");
}

writedump(var=capturedOrder, label="capture");

// return to edit the CC info
if (!isCaptured){
	writeoutput("<p>Capture failed. Redisplay form to allow corrections...</p>");
	exit;
}
writeoutput("<p>Save the order data with transaction ID #capturedOrder.transactionId#.</p>");

</cfscript>
