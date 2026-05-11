const User = require('../models/User');
const BpmRecord = require('../models/BpmRecord');
const BreathingRecord = require('../models/BreathingRecord');
const jwt = require('jsonwebtoken');
const { sendOTPEmail } = require('../utils/mailer');

exports.sendOTP = async (req, res) => {
    try {
        const email = req.body.email?.trim().toLowerCase();
        
        // Generate 6 digit OTP
        const otp = Math.floor(100000 + Math.random() * 900000).toString();
        const otpExpires = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes
        
        console.log('\n' + '='.repeat(50));
        console.log(`\x1b[33m%s\x1b[0m`, `[DEV] VERIFICATION CODE FOR ${email}:`);
        console.log(`\x1b[31;1m%s\x1b[0m`, `      >>> ${otp} <<<`);
        console.log('='.repeat(50) + '\n');

        // Find user by email (don't create yet if they don't exist, or update if they do)
        let user = await User.findOne({ email });
        
        if (user) {
            user.otp = otp;
            user.otpExpires = otpExpires;
            await user.save();
        } else {
            // For new users, we'll create a temporary record or handle it during registration
            // Here we'll just allow it for now, assuming the register call comes later
            // Actually, it's better to create the user with a temporary password or just wait for registration
            // For this flow, let's just send the email and verify it later
        }

        const emailSent = await sendOTPEmail(email, otp);
        if (emailSent) {
            res.status(200).json({ message: 'OTP sent successfully' });
        } else {
            res.status(500).json({ message: 'Error sending OTP email' });
        }
    } catch (error) {
        console.error('Send OTP error:', error);
        res.status(500).json({ message: error.message });
    }
};

exports.verifyOTP = async (req, res) => {
    try {
        const email = req.body.email?.trim().toLowerCase();
        const { otp } = req.body;
        
        // This is a simplified check. In a real app, you'd check the database.
        // Since we might not have a user yet, we'd need a way to store these temporarily.
        // For now, let's assume the user was created during registration (step 1) or we'll just verify against a mock/stored value.
        
        const user = await User.findOne({ email, otp, otpExpires: { $gt: Date.now() } });
        
        if (!user) {
            return res.status(400).json({ message: 'Invalid or expired OTP' });
        }

        if (!user.isVerified) {
            user.isVerified = true;
            user.otp = undefined;
            user.otpExpires = undefined;
            await user.save();
        }

        const token = jwt.sign({ id: user._id.toString() }, process.env.JWT_SECRET, { expiresIn: '7d' });
        res.status(200).json({ 
            message: 'OTP verified successfully',
            token: token,
            id: user._id,
            name: user.name,
            email: email,
            profileImage: user.profileImage,
            dob: user.dob,
            gender: user.gender,
            healthGoals: user.healthGoals,
            achievements: user.achievements,
            scanStreak: user.scanStreak,
            breathingStreak: user.breathingStreak,
            isTwoFactorEnabled: user.isTwoFactorEnabled,
            subscriptionType: user.subscriptionType,
            subscriptionExpiry: user.subscriptionExpiry
        });
    } catch (error) {
        console.error('Verify OTP error:', error);
        res.status(500).json({ message: error.message });
    }
};

exports.register = async (req, res) => {
    try {
        console.log('Registration attempt for:', req.body.email);
        const { name, password } = req.body;
        const email = req.body.email?.trim().toLowerCase();
        
        console.log('Checking if user exists...');
        let user = await User.findOne({ email });
        if (user && user.isVerified) {
            console.log('User already exists');
            return res.status(400).json({ message: 'User already exists' });
        }

        if (user) {
            // Update existing unverified user
            user.name = name;
            user.password = password;
        } else {
            // Create new unverified user
            user = new User({ name, email, password });
        }
        
        await user.save();
        console.log('User saved successfully');

        // We don't send the token yet, we wait for OTP verification
        res.status(201).json({ 
            id: user._id, 
            name: user.name, 
            email: user.email, 
            message: 'User created. Please verify OTP.' 
        });
    } catch (error) {
        console.error('Registration error details:', error);
        res.status(500).json({ message: error.message });
    }
};

exports.login = async (req, res) => {
    try {
        const { password } = req.body;
        const email = req.body.email?.trim().toLowerCase();
        
        const user = await User.findOne({ email });
        if (!user) return res.status(400).json({ message: 'Invalid credentials' });

        if (!user.isVerified) {
            return res.status(401).json({ message: 'Please verify your email first', email: email });
        }

        const isMatch = await user.comparePassword(password);
        if (!isMatch) return res.status(400).json({ message: 'Invalid credentials' });



        const token = jwt.sign({ id: user._id.toString() }, process.env.JWT_SECRET, { expiresIn: '7d' });
        res.json({ 
            token: token, 
            id: user._id, 
            name: user.name, 
            email: email,
            profileImage: user.profileImage,
            dob: user.dob,
            gender: user.gender,
            healthGoals: user.healthGoals,
            achievements: user.achievements,
            scanStreak: user.scanStreak,
            breathingStreak: user.breathingStreak,
            isTwoFactorEnabled: user.isTwoFactorEnabled,
            subscriptionType: user.subscriptionType,
            subscriptionExpiry: user.subscriptionExpiry
        });
    } catch (error) {
        console.error('Login error:', error);
        res.status(500).json({ message: error.message });
    }
};

exports.forgotPassword = async (req, res) => {
    try {
        const email = req.body.email?.trim().toLowerCase();
        if (!email) return res.status(400).json({ message: 'Email is required' });

        const user = await User.findOne({ email });
        if (!user || !user.isVerified) {
            return res.status(404).json({ message: 'Email not registered' });
        }

        // Generate 6 digit OTP
        const otp = Math.floor(100000 + Math.random() * 900000).toString();
        const otpExpires = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

        user.otp = otp;
        user.otpExpires = otpExpires;
        await user.save();
        
        console.log(`\x1b[33m%s\x1b[0m`, `[DEV] Password Reset OTP for ${email}: ${otp}`);

        const emailSent = await sendOTPEmail(email, otp);
        if (emailSent) {
            res.status(200).json({ message: 'OTP sent successfully' });
        } else {
            res.status(500).json({ message: 'Error sending OTP email' });
        }
    } catch (error) {
        console.error('Forgot password error:', error);
        res.status(500).json({ message: error.message });
    }
};

exports.resetPassword = async (req, res) => {
    try {
        const email = req.body.email?.trim().toLowerCase();
        const { otp, password } = req.body;

        if (!email || !otp || !password) {
            return res.status(400).json({ message: 'Email, OTP and new password are required' });
        }

        const user = await User.findOne({ 
            email, 
            otp, 
            otpExpires: { $gt: Date.now() } 
        });

        if (!user) {
            return res.status(400).json({ message: 'Invalid or expired OTP' });
        }

        user.password = password; // pre-save hook will hash it
        user.otp = undefined;
        user.otpExpires = undefined;
        await user.save();

        res.status(200).json({ message: 'Password updated successfully' });
    } catch (error) {
        console.error('Reset password error:', error);
        res.status(500).json({ message: error.message });
    }
};

exports.updateProfileImage = async (req, res) => {
    try {
        const { userId } = req.body;
        console.log(`Profile image update request for user: ${userId}`);
        
        if (!req.file) {
            console.log('No file received in request');
            return res.status(400).json({ message: 'No image file provided' });
        }
        console.log(`File received: ${req.file.filename}, size: ${req.file.size}`);

        const user = await User.findById(userId);
        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }

        // Store the relative path
        user.profileImage = `/uploads/${req.file.filename}`;
        await user.save();

        res.status(200).json({ 
            message: 'Profile image updated', 
            profileImage: user.profileImage 
        });
    } catch (error) {
        console.error('Update profile image error:', error);
        res.status(500).json({ message: error.message });
    }
};

exports.updateUserProfile = async (req, res) => {
    try {
        const { userId, name, dob, gender } = req.body;
        const user = await User.findById(userId);
        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }

        if (name) user.name = name;
        if (dob) user.dob = dob;
        if (gender) user.gender = gender;

        await user.save();

        res.status(200).json({ 
            message: 'Profile updated successfully',
            user: {
                id: user._id,
                name: user.name,
                email: user.email,
                dob: user.dob,
                gender: user.gender,
                profileImage: user.profileImage,
                healthGoals: user.healthGoals,
                achievements: user.achievements,
                scanStreak: user.scanStreak,
                scanStreak: user.scanStreak,
                breathingStreak: user.breathingStreak,
                isTwoFactorEnabled: user.isTwoFactorEnabled,
                subscriptionType: user.subscriptionType,
                subscriptionExpiry: user.subscriptionExpiry
            }
        });
    } catch (error) {
        console.error('Update profile error:', error);
        res.status(500).json({ message: error.message });
    }
};

exports.updateHealthGoals = async (req, res) => {
    try {
        const { userId, healthGoals } = req.body;
        const user = await User.findById(userId);
        if (!user) return res.status(404).json({ message: 'User not found' });

        user.healthGoals = { ...user.healthGoals.toObject(), ...healthGoals };
        await user.save();

        res.status(200).json({ message: 'Health goals updated', healthGoals: user.healthGoals });
    } catch (error) {
        console.error('Update health goals error:', error);
        res.status(500).json({ message: error.message });
    }
};
exports.toggle2FA = async (req, res) => {
    try {
        const { userId, enabled } = req.body;
        const user = await User.findById(userId);
        if (!user) return res.status(404).json({ message: 'User not found' });

        user.isTwoFactorEnabled = enabled;
        await user.save();

        res.status(200).json({ message: `Two-factor authentication ${enabled ? 'enabled' : 'disabled'}` });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
exports.getHealthStatus = async (req, res) => {
    try {
        const { userId } = req.params;
        const user = await User.findById(userId);
        if (!user) return res.status(404).json({ message: 'User not found' });

        const startOfDay = new Date();
        startOfDay.setHours(0, 0, 0, 0);

        const todayScans = await BpmRecord.countDocuments({
            userId: userId,
            timestamp: { $gte: startOfDay }
        });

        const todayBreathingRecords = await BreathingRecord.find({
            userId: userId,
            timestamp: { $gte: startOfDay }
        });

        const totalBreathingMinutes = todayBreathingRecords.reduce((sum, record) => sum + record.duration, 0);

        console.log(`User ${userId} has ${todayScans} scans and ${totalBreathingMinutes} mins breathing today`);

        res.status(200).json({
            healthGoals: user.healthGoals,
            progress: {
                scansCompleted: todayScans,
                breathingMinutes: totalBreathingMinutes
            },
            achievements: user.achievements,
            scanStreak: user.scanStreak,
            breathingStreak: user.breathingStreak,
            subscriptionType: user.subscriptionType,
            subscriptionExpiry: user.subscriptionExpiry
        });
    } catch (error) {
        console.error('Get health status error:', error);
        res.status(500).json({ message: error.message });
    }
};
exports.changePassword = async (req, res) => {
    try {
        const { userId, currentPassword, newPassword } = req.body;
        const user = await User.findById(userId);
        if (!user) return res.status(404).json({ message: 'User not found' });

        const isMatch = await user.comparePassword(currentPassword);
        if (!isMatch) return res.status(400).json({ message: 'Incorrect current password' });

        user.password = newPassword;
        await user.save();

        res.status(200).json({ message: 'Password changed successfully' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
exports.deleteAccount = async (req, res) => {
    try {
        const { userId, password } = req.body;
        const user = await User.findById(userId);
        if (!user) return res.status(404).json({ message: 'User not found' });

        const isMatch = await user.comparePassword(password);
        if (!isMatch) return res.status(400).json({ message: 'Incorrect password' });

        // Delete associated data
        await BpmRecord.deleteMany({ userId });
        await BreathingRecord.deleteMany({ userId });
        
        // Delete user
        await User.findByIdAndDelete(userId);

        res.status(200).json({ message: 'Account deleted successfully' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.updateSubscription = async (req, res) => {
    try {
        const { userId, subscriptionType, subscriptionExpiry } = req.body;
        const user = await User.findById(userId);
        if (!user) return res.status(404).json({ message: 'User not found' });

        user.subscriptionType = subscriptionType;
        user.subscriptionExpiry = subscriptionExpiry;
        await user.save();

        res.status(200).json({ 
            message: 'Subscription updated', 
            subscriptionType: user.subscriptionType,
            subscriptionExpiry: user.subscriptionExpiry 
        });
    } catch (error) {
        console.error('Update subscription error:', error);
        res.status(500).json({ message: error.message });
    }
};
