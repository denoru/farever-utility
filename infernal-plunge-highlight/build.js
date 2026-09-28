const fs = require('fs');
const path = require('path');
const archiver = require('archiver');

const ROOT = __dirname;
const BUILD_DIR = path.join(ROOT, 'build');
const DIST_DIR = path.join(ROOT, 'dist');
const GAME_DIR = 'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Farever';
const PACKAGE_JSON = path.join(ROOT, 'package.json');

function ensureDir(dir) {
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function zipDirectory() {
    const archivePath = path.join(DIST_DIR, 'farever-infernal-plunge-highlight.zip');
    ensureDir(DIST_DIR);

    const output = fs.createWriteStream(archivePath);
    const archive = archiver('zip', { zlib: { level: 9 } });

    output.on('close', () => {
        console.log(`ZIP created: ${archivePath} (${archive.pointer()} bytes)`);
    });

    archive.on('error', (err) => { throw err; });
    archive.pipe(output);

    function addFiles(dir, basePath) {
        if (!fs.existsSync(dir)) return;
        const entries = fs.readdirSync(dir);
        for (const entry of entries) {
            const fullPath = path.join(dir, entry);
            const relPath = path.join(basePath, entry);
            const stat = fs.statSync(fullPath);
            if (stat.isDirectory()) {
                addFiles(fullPath, relPath);
            } else {
                archive.file(fullPath, { name: relPath });
            }
        }
    }

    // Add .hl file and info.json
    const hlDir = path.join(ROOT, 'hlx', 'mods', 'infernal-plunge-highlight');
    if (fs.existsSync(hlDir)) {
        addFiles(hlDir, 'hlx/mods/infernal-plunge-highlight');
    }

    // Add src
    if (fs.existsSync(path.join(ROOT, 'src'))) {
        addFiles(path.join(ROOT, 'src'), 'src');
    }

    // Add docs
    if (fs.existsSync(path.join(ROOT, 'docs'))) {
        addFiles(path.join(ROOT, 'docs'), 'docs');
    }

    // info.json
    const info = {
        name: "farever-infernal-plunge-highlight",
        displayName: "Infernal Plunge Highlighter",
        description: "Highlights Infernal Plunge (Rogue) when target has Chaos Mark.",
        version: "1.0.0",
        author: "Denoru",
        game: "farever",
        steamAppId: 3672400,
        modType: "hlx",
        runtime: "hlmod",
        minFareverVersion: "1.0.0",
        class: "Rogue",
        skill: "Infernal Plunge",
        trigger: "Chaos Mark"
    };
    fs.writeFileSync(path.join(BUILD_DIR, 'info.json'), JSON.stringify(info, null, 2));
    archive.file(path.join(BUILD_DIR, 'info.json'), { name: 'info.json' });

    // gameart.png
    const gameart = Buffer.from(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        'base64'
    );
    fs.writeFileSync(path.join(BUILD_DIR, 'gameart.png'), gameart);
    archive.file(path.join(BUILD_DIR, 'gameart.png'), { name: 'gameart.png' });

    archive.finalize();
}

function build() {
    const pkg = JSON.parse(fs.readFileSync(PACKAGE_JSON, 'utf8'));
    ensureDir(BUILD_DIR);
    ensureDir(DIST_DIR);

    // Clean build dir
    if (fs.existsSync(BUILD_DIR)) {
        fs.rmSync(BUILD_DIR, { recursive: true });
    }
    ensureDir(BUILD_DIR);

    // Compile Haxe to .hl
    const haxePath = 'C:\\HaxeToolkit\\haxe_20240807093059_760c0dd\\haxe.exe';
    const srcDir = path.join(ROOT, 'src');
    const hlxRuntimeDir = process.env.HLX_RUNTIME_SRC || path.join(ROOT, '..', 'hlx-core', 'hlx-runtime', 'src');
    const hlImguiDir = process.env.HL_IMGUI_SRC || path.join(ROOT, '..', 'hl-imgui', 'src');
    const hlOutput = path.join(GAME_DIR, 'hlx', 'mods', 'infernal-plunge-highlight', 'infernal-plunge-highlight.hl');

    if (fs.existsSync(haxePath) && fs.existsSync(srcDir)) {
        console.log('Compiling Haxe to HashLink bytecode...');
        const { execSync } = require('child_process');
        try {
            const cmd = `"${haxePath}" -cp "${srcDir}" -cp "${hlxRuntimeDir}" -cp "${hlImguiDir}" -main Main -hl "${hlOutput}"`;
            console.log('Command:', cmd);
            execSync(cmd, { stdio: 'inherit' });
            console.log('Compilation successful!');
        } catch (e) {
            console.error('Compilation failed:', e.message);
            process.exit(1);
        }
    } else {
        console.log('Skipping compilation (Haxe or source not found)');
    }

    // ZIP
    zipDirectory();

    console.log('\nBuild complete!');
    console.log(`Deployed: ${hlOutput}`);
    console.log(`Package: ${path.join(DIST_DIR, 'farever-infernal-plunge-highlight.zip')}`);
}

build();
