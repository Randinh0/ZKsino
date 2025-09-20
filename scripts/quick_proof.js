#!/usr/bin/env node

const { execSync } = require('child_process');
const path = require('path');

console.log('🚀 Generación rápida de prueba ZK\n');

try {
    // Ejecutar el script principal
    const scriptPath = path.join(__dirname, 'generate_and_verify_proof.js');
    execSync(`node "${scriptPath}"`, { stdio: 'inherit' });
    
    console.log('\n✨ ¡Listo! Archivos en temp/');
    
} catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
}
