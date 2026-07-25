/**
 * Win11Debloat - Debloat Engine (Node.js)
 * Location: utils/DebloatEngine.js
 *
 * Core JSON configuration validator and command execution wrapper.
 * Used by EdgeBlocker.js and future JS modules.
 */

const fs = require('fs');
const path = require('path');
const { execSync, spawn } = require('child_process');

function resolveConfig(relativePath) {
    const resolved = path.join(__dirname, '..', 'config', relativePath);
    if (!fs.existsSync(resolved)) {
        throw new Error(`Config file not found: ${resolved}`);
    }
    return resolved;
}

function loadConfig(relativePath) {
    const configPath = resolveConfig(relativePath);
    const raw = fs.readFileSync(configPath, 'utf8');
    try {
        return JSON.parse(raw);
    } catch (err) {
        throw new Error(`Invalid JSON in ${configPath}: ${err.message}`);
    }
}

function runCommand(cmd, options = {}) {
    try {
        const result = execSync(cmd, {
            encoding: 'utf8',
            stdio: options.silent ? 'pipe' : 'inherit',
            ...options
        });
        return { success: true, output: result };
    } catch (err) {
        return {
            success: false,
            output: err.stderr ? err.stderr.toString() : err.message
        };
    }
}

function killProcess(imageName) {
    return runCommand(`taskkill /F /IM ${imageName} /T 2>nul`, { silent: true });
}

function setRegistryValue(regPath, name, type, value) {
    const sanitizedType = type.toUpperCase();
    const cmd = `reg add "${regPath}" /v "${name}" /t REG_${sanitizedType} /d ${value} /f`;
    return runCommand(cmd, { silent: true });
}

module.exports = {
    resolveConfig,
    loadConfig,
    runCommand,
    killProcess,
    setRegistryValue
};
