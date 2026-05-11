require('dotenv').config();
const { sendOTPEmail } = require('./utils/mailer');

async function test() {
    console.log('Testing email sending...');
    console.log('API Key:', process.env.BREVO_API_KEY ? 'Present' : 'Missing');
    console.log('Sender Email:', process.env.BREVO_SENDER_EMAIL);
    
    const result = await sendOTPEmail('padalavenkatareddy2006@gmail.com', '123456');
    if (result) {
        console.log('Test email sent successfully!');
    } else {
        console.log('Failed to send test email.');
    }
}

test();
