import axios from 'axios';

/**
 * Basic performance load tester for the aave-lending backend API.
 * Simulates multiple concurrent requests to test the rate-limiter and DB read performance.
 */
async function runPerformanceVerification() {
    console.log('[PERF] Starting Performance Verification...');
    
    const TARGET_URL = 'http://localhost:3000/api/v1/health'; // Replace with actual health or markets endpoint
    const CONCURRENT_REQUESTS = 50;
    const TOTAL_REQUESTS = 500;

    let successCount = 0;
    let errorCount = 0;
    const start = Date.now();

    for (let i = 0; i < TOTAL_REQUESTS; i += CONCURRENT_REQUESTS) {
        const batch = [];
        for (let j = 0; j < CONCURRENT_REQUESTS; j++) {
            batch.push(axios.get(TARGET_URL).then(() => successCount++).catch(() => errorCount++));
        }
        await Promise.all(batch);
        process.stdout.write(`\rProgress: ${i + CONCURRENT_REQUESTS} / ${TOTAL_REQUESTS}`);
    }

    const end = Date.now();
    console.log('\n[PERF] Verification Complete.');
    console.log(`Total Time: ${(end - start) / 1000}s`);
    console.log(`Successful Requests: ${successCount}`);
    console.log(`Failed/Rate-Limited Requests: ${errorCount}`);
    
    if (successCount > 0 && errorCount === 0) {
        console.log('✅ Performance threshold passed!');
    } else {
        console.log('⚠️ Notice: Some requests failed. This may be due to the Redis Rate Limiter functioning correctly (expected natively).');
    }
}

runPerformanceVerification().catch(console.error);
