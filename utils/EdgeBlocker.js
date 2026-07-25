/**
 * Win11Debloat - Edge Neutralizer Module (Node.js)
 * Location: utils/EdgeBlocker.js
 *
 * Reads config/edge_block.json and applies:
 *  - IFEO execution redirect on msedge.exe
 *  - Anti-reinstall registry policies
 *  - Active Edge process termination
 */

const fs = require('fs');
const path = require('path');
const engine = require('./DebloatEngine.js');

function applyEdgeBlock() {
    console.log('[*] Reading Edge Block Configuration...');
    let config;
    try {
        config = engine.loadConfig('edge_block.json');
    } catch (err) {
        console.error('[-] ' + err.message);
        process.exit(1);
    }

    // 1. Apply anti-reinstall registry policies
    if (config.registryKeys && Array.isArray(config.registryKeys)) {
        console.log('[*] Applying Anti-Reinstall Registry Policies...');
        config.registryKeys.forEach((item) => {
            const result = engine.setRegistryValue(item.path, item.name, item.type, item.value);
            if (result.success) {
                console.log(`[+] Set ${item.path}\\${item.name} = ${item.value}`);
            } else {
                console.warn(`[!] Failed to set ${item.path}\\${item.name}: ${result.output}`);
            }
        });
    }

    // 2. Apply IFEO redirect (blocks msedge.exe execution permanently)
    if (config.ifeoBlock) {
        console.log('[*] Registering Image File Execution Options (IFEO) Redirect...');
        const ifeoPath = `HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options\\${config.ifeoBlock.targetExecutable}`;
        const result = engine.setRegistryValue(ifeoPath, 'Debugger', 'REG_SZ', config.ifeoBlock.debuggerRedirect);
        if (result.success) {
            console.log(`[+] IFEO block placed on ${config.ifeoBlock.targetExecutable}`);
        } else {
            console.warn(`[!] Failed to set IFEO redirect: ${result.output}`);
        }
    }

    // 3. Kill active Edge processes
    console.log('[*] Terminating active Edge processes...');
    const killResult = engine.killProcess('msedge.exe');
    if (killResult.success) {
        console.log('[+] Active Edge processes terminated.');
    } else {
        console.warn(`[!] Edge process termination note: ${killResult.output}`);
    }

    console.log('[+] Edge blocking rules applied successfully.');
}

applyEdgeBlock();
