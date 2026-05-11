const express = require('express');
const { register, login, sendOTP, verifyOTP, forgotPassword, resetPassword, updateProfileImage, updateUserProfile, updateHealthGoals, getHealthStatus, toggle2FA, changePassword, deleteAccount, updateSubscription } = require('../controllers/authController');
const upload = require('../utils/upload');
const router = express.Router();

router.post('/register', register);
router.post('/login', login);
router.post('/send-otp', sendOTP);
router.post('/verify-otp', verifyOTP);
router.post('/forgot-password', forgotPassword);
router.post('/reset-password', resetPassword);
router.post('/update-profile-image', upload.single('image'), updateProfileImage);
router.post('/update-profile', updateUserProfile);
router.post('/health-goals', updateHealthGoals);
router.post('/toggle-2fa', toggle2FA);
router.post('/change-password', changePassword);
router.post('/delete-account', deleteAccount);
router.post('/update-subscription', updateSubscription);
router.get('/health-status/:userId', getHealthStatus);

module.exports = router;
