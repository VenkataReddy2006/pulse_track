const express = require('express');
const { addRecord, getHistory, getLatest, getStats } = require('../controllers/bpmController');
const router = express.Router();

router.post('/add', addRecord);
router.get('/history/:userId', getHistory);
router.get('/latest/:userId', getLatest);
router.get('/stats/:userId', getStats);

module.exports = router;
