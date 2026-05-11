const express = require('express');
const { addBreathingRecord, getBreathingHistory } = require('../controllers/breathingController');
const router = express.Router();

router.post('/add', addBreathingRecord);
router.get('/history/:userId', getBreathingHistory);

module.exports = router;
