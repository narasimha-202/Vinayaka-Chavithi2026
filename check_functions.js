const fs = require('fs');
const html = fs.readFileSync('index.html', 'utf8');

const scriptContent = html.match(/<script>([\s\S]*?)<\/script>/g).join('\n');
const onclicks = [...html.matchAll(/onclick="([^"]+)"/g)].map(m => m[1]);

const fnNames = new Set();
onclicks.forEach(c => {
    const expr = c.split(';')[0];
    const name = expr.split('(')[0].trim();
    if (name && !name.includes('.') && !name.includes('=')) {
        fnNames.add(name);
    }
});

console.log('Checking onclick handler functions:');
let missingCount = 0;
fnNames.forEach(fn => {
    const regex = new RegExp(`function\\s+${fn}\\b`);
    if (!regex.test(scriptContent)) {
        console.error('❌ MISSING FUNCTION:', fn);
        missingCount++;
    } else {
        console.log('✓ Found:', fn);
    }
});

if (missingCount === 0) {
    console.log('✅ ALL ONCLICK FUNCTIONS EXIST!');
} else {
    console.log(`❌ ${missingCount} FUNCTIONS MISSING!`);
}
