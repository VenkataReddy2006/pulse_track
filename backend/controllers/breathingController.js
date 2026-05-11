const BreathingRecord = require('../models/BreathingRecord');
const User = require('../models/User');

exports.addBreathingRecord = async (req, res) => {
    try {
        const { userId, duration } = req.body;
        const newRecord = new BreathingRecord({ userId, duration });
        await newRecord.save();

        // Breathing Streak Logic
        const user = await User.findById(userId);
        if (user) {
            const startOfDay = new Date();
            startOfDay.setHours(0, 0, 0, 0);

            const todayRecords = await BreathingRecord.find({
                userId,
                timestamp: { $gte: startOfDay }
            });

            const todayMinutes = todayRecords.reduce((sum, r) => sum + r.duration, 0);
            const dailyGoal = user.healthGoals?.dailyBreathingGoal || 5;

            if (todayMinutes >= dailyGoal) {
                const now = new Date();
                const lastUpdate = user.lastBreathingStreakUpdate;
                
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
                        user.breathingStreak += 1;
                    } else {
                        user.breathingStreak = 1;
                    }
                    user.lastBreathingStreakUpdate = now;
                    await user.save();
                    console.log(`User ${userId} reached breathing goal! Streak: ${user.breathingStreak}`);
                }
            }
        }

        res.status(201).json(newRecord);
    } catch (error) {
        console.error('Add breathing record error:', error);
        res.status(500).json({ message: error.message });
    }
};

exports.getBreathingHistory = async (req, res) => {
    try {
        const { userId } = req.params;
        const history = await BreathingRecord.find({ userId }).sort({ timestamp: -1 });
        res.json(history);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
