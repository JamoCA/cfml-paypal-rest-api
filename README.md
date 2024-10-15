# cfml-paypal-rest-api
ColdFusion/CFML CFC for transacting a credit card using PayPal REST API with [Advanced Credit and Debit Card Payments](https://www.paypal.com/us/cshelp/article/what-is-paypal-advanced-checkout-and-how-do-i-get-started-help95).

Important: You'll need a [PayPal Business account](https://www.paypal.com/business/open-business-account) to do the following:
- Go live with integrations.
- Test integrations outside the US.

Here's how to get your client ID and client secret:
- Select [Log in to Dashboard](https://developer.paypal.com/dashboard/) and log in or sign up.
- Select **Apps & Credentials**.
- New accounts come with a **Default Application** in the **REST API apps** section. To create a new project, select **Create App**.
- View app details and enable "Advanced Credit and Debit Card Payments"
- Copy the client ID and client secret for your app.
- Using "Live mode" requires approval from PayPal, but you can test using the sandbox.

## 1. Initialize the CFC

```cfc
payPalApi = new PaypalRestAPI(
	clientId = "[PayPal API ClientID]",
	clientSecret = "[PayPal API Secret]",
	descriptor = "My Big Business Name", // <= 22 chars; printed on CC statement
	developmentMode = true
);
```

## 2. Create a Unique ID

```cfc
// REQUIRED: create unique ID for tracking order
requestId = createuuid();
```

## 3. Create an Order

```cfc
order = payPalApi.createOrder(
requestId = requestId
	amount = 14.99,
	name = "Joe Cardholder",
	cardnumber = "4556747948786484",
	expdate = dateadd("m", 2, now()), // format "yyyy-mm" or pass a date object
	cvv2 = "789",
	address = "123 ABC Street", // optional
	city = "Anytown", // optional (admin_area_2)
	state = "CA", // optional  (admin_area_1)
	zip = "90210", // optional (postal_code)
	country = "US" // optional
);

if (order.responseCode neq "0000"){
	writeoutput("<p style=""color:red;""><b>Order Error:</b> #order.errorMessage#</p>");
	// Redisplay form to allow corrections
	exit;
}
```

## 4. Capture the Order (if the order creation was successful)

```cfc
capturedOrder = payPalApi.captureOrder(
	requestId = requestId,
	id = order.id
);
if (capturedOrder.responseCode neq "0000"){
	writeoutput("<p style=""color:red;""><b>Capture Error:</b> #capturedOrder.errorMessage#</p>");
	// Redisplay form to allow corrections
	exit;
}
// Save the order data.
writeoutput("<p>Paypal Transaction ID #capturedOrder.id#.</p>");
```

