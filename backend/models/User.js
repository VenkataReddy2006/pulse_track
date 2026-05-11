const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema({
    name: {
        type: String,
        required: true
    },
    email: {
        type: String,
        required: true,
        unique: true
    },
    password: {
        type: String,
        required: true
    },
    otp: {
        type: String
    },
    otpExpires: {
        type: Date
    },
    isVerified: {
        type: Boolean,
        default: false
    },
    isTwoFactorEnabled: {
        type: Boolean,
        default: false
    },
    profileImage: {
        type: String
    },
    dob: {
        type: String
    },
    gender: {
        type: String
    },
    healthGoals: {
        targetHeartRate: {
            min: { type: Number, default: 60 },
            max: { type: Number, default: 90 }
        },
        dailyScanGoal: { type: Number, default: 3 },
        dailyBreathingGoal: { type: Number, default: 5 },
        weeklyBpmTarget: { type: Number, default: 85 }
    },
    achievements: {
        type: [String],
        default: []
    },
    scanStreak: {
        type: Number,
        default: 0
    },
    lastStreakUpdate: {
        type: Date
    },
    breathingStreak: {
        type: Number,
        default: 0
    },
    lastBreathingStreakUpdate: {
        type: Date
    },
    subscriptionType: {
        type: String,
        default: null
    },
    subscriptionExpiry: {
        type: Date,
        default: null
    }
}, { timestamps: true });

// Hash password before saving
userSchema.pre('save', async function() {
    if (!this.isModified('password')) return;
    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
});

// Compare password
userSchema.methods.comparePassword = async function(password) {
    return await bcrypt.compare(password, this.password);
};

module.exports = mongoose.model('User', userSchema);
