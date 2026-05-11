const BpmRecord = require('../models/BpmRecord');
const User = require('../models/User');

exports.addRecord = async (req, res) => {
    try {
        const { userId, bpm, status, spo2, systolic, diastolic, bloodPressure } = req.body;
        const newRecord = new BpmRecord({ userId, bpm, status, spo2, systolic, diastolic, bloodPressure });
        await newRecord.save();

        // Streak Logic
        const user = await User.findById(userId);
        if (user) {
            const startOfDay = new Date();
            startOfDay.setHours(0, 0, 0, 0);

            const todayScans = await BpmRecord.countDocuments({
                userId,
                timestamp: { $gte: startOfDay }
            });

            const dailyGoal = user.healthGoals?.dailyScanGoal || 3;

            if (todayScans >= dailyGoal) {
                const now = new Date();
                const lastUpdate = user.lastStreakUpdate;
                
                let isAlreadyUpdatedToday = false;
                if (lastUpdate) {
                    const lastUpdateDate = new Date(lastUpdate);
                    isAlreadyUpdatedToday = lastUpdateDate.toDateString() === now.toDateString();
                }

                if (!isAlreadyUpdatedToday) {
                    // Check if last update was yesterday
                    const yesterday = new Date();
                    yesterday.setDate(yesterday.getDate() - 1);
                    const wasYesterday = lastUpdate && new Date(lastUpdate).toDateString() === yesterday.toDateString();

                    if (wasYesterday) {
                        user.scanStreak += 1;
                    } else {
                        user.scanStreak = 1;
                    }
                    user.lastStreakUpdate = now;
                    await user.save();
                    console.log(`User ${userId} reached daily goal! Streak: ${user.scanStreak}`);
                }
            }
        }

        res.status(201).json(newRecord);
    } catch (error) {
        console.error('Add record error:', error);
        res.status(500).json({ message: error.message });
    }
};

exports.getHistory = async (req, res) => {
    try {
        const { userId } = req.params;
        const history = await BpmRecord.find({ userId }).sort({ timestamp: -1 });
        res.json(history);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.getLatest = async (req, res) => {
    try {
        const { userId } = req.params;
        const latest = await BpmRecord.findOne({ userId }).sort({ timestamp: -1 });
        res.json(latest);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

exports.getStats = async (req, res) => {
    try {
        const { userId } = req.params;
        const records = await BpmRecord.find({ userId });
        
        if (records.length === 0) {
            return res.json({ avgBpm: 0, maxBpm: 0, minBpm: 0, totalScans: 0 });
        }

        const bpms = records.map(r => r.bpm);
        const avgBpm = Math.round(bpms.reduce((a, b) => a + b, 0) / bpms.length);
        const maxBpm = Math.max(...bpms);
        const minBpm = Math.min(...bpms);
        const totalScans = records.length;

        res.json({ avgBpm, maxBpm, minBpm, totalScans });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
