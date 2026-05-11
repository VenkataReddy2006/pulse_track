const mongoose = require('mongoose');

const bpmRecordSchema = new mongoose.Schema({
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    bpm: {
        type: Number,
        required: true
    },
    status: {
        type: String,
        required: true
    },
    spo2: {
        type: Number,
        required: false
    },
    systolic: {
        type: Number,
        required: false
    },
    diastolic: {
        type: Number,
        required: false
    },
    bloodPressure: {
        type: String,
        required: false
    },
    timestamp: {
        type: Date,
        default: Date.now
    }
}, { timestamps: true });

module.exports = mongoose.model('BpmRecord', bpmRecordSchema);
