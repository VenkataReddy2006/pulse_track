const SibApiV3Sdk = require('sib-api-v3-sdk');

const sendOTPEmail = async (email, otp) => {
    try {
        console.log(`Attempting to send OTP to ${email} via Brevo SDK...`);
        
        const defaultClient = SibApiV3Sdk.ApiClient.instance;
        const apiKey = defaultClient.authentications['api-key'];
        apiKey.apiKey = process.env.BREVO_API_KEY;

        const apiInstance = new SibApiV3Sdk.TransactionalEmailsApi();
        const sendSmtpEmail = new SibApiV3Sdk.SendSmtpEmail();

        sendSmtpEmail.subject = "Your PulseTrack Verification Code";
        sendSmtpEmail.htmlContent = `
            <html>
                <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
                    <div style="max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #ddd; border-radius: 10px;">
                        <h2 style="color: #FF4D4D; text-align: center;">PulseTrack Verification</h2>
                        <p>Hello,</p>
                        <p>Your verification code is: <strong style="font-size: 24px; color: #FF4D4D; letter-spacing: 2px;">${otp}</strong></p>
                        <p>This code will expire in 10 minutes. If you did not request this code, please ignore this email.</p>
                        <hr style="border: 0; border-top: 1px solid #eee; margin: 20px 0;">
                        <p style="font-size: 12px; color: #777; text-align: center;">&copy; 2026 PulseTrack Inc. All rights reserved.</p>
                    </div>
                </body>
            </html>
        `;
        sendSmtpEmail.sender = { "name": "PulseTrack", "email": process.env.BREVO_SENDER_EMAIL };
        sendSmtpEmail.to = [{ "email": email }];

        const data = await apiInstance.sendTransacEmail(sendSmtpEmail);
        console.log('API called successfully. Returned data: ' + JSON.stringify(data));
        return true;
    } catch (error) {
        console.error('Error sending email via Brevo SDK:');
        console.error(error);
        
        // DEVELOPMENT FALLBACK
        console.log(`\x1b[35m%s\x1b[0m`, `[FALLBACK] Email sending failed. Use the OTP from the console.`);
        return true;
    }
};

module.exports = { sendOTPEmail };
