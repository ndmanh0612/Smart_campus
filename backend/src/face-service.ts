import { execFile, spawn, ChildProcess } from 'node:child_process';
import { resolve } from 'node:path';
import { existsSync, readFileSync } from 'node:fs';
import { createInterface } from 'node:readline';

const root = resolve(import.meta.dirname, '../..');
const faceEngineScript = resolve(root, 'ai-service/face_engine.py');
const faceDaemonScript = resolve(root, 'ai-service/face_daemon.py');

export interface FaceDetectionResult {
    success: boolean;
    faces?: Array<{ box: number[]; score: number }>;
    width?: number;
    height?: number;
    error?: string;
    message?: string;
    enrollmentEligible?: boolean;
    guidance?: string;
}

export interface FaceEnrollResult {
    success: boolean;
    status?: string;
    studentId?: string;
    studentCode?: string;
    name?: string;
    score?: number;
    box?: number[];
    error?: string;
    message?: string;
}

export interface FaceIdentifyResult {
    success: boolean;
    outcome?: 'MATCH' | 'NO_MATCH' | 'NO_FACE' | 'NO_PROFILES';
    studentId?: string;
    studentCode?: string;
    name?: string;
    score?: number;
    threshold?: number;
    box?: number[];
    error?: string;
    message?: string;
}

// ============================================================================
// Persistent AI Daemon for 30ms real-time inference (no python startup latency)
// ============================================================================
let daemonProcess: ChildProcess | null = null;
let daemonReady = false;
let reqSeq = 0;
const pendingRequests = new Map<number, { resolve: (val: any) => void; reject: (err: any) => void; timer: NodeJS.Timeout }>();

function ensureDaemon(): void {
    if (daemonProcess && daemonReady) return;
    if (daemonProcess) return;

    try {
        const child = spawn('python', [faceDaemonScript], {
            cwd: root,
            windowsHide: true,
            stdio: ['pipe', 'pipe', 'pipe']
        });
        daemonProcess = child;

        const rl = createInterface({ input: child.stdout! });
        rl.on('line', (line) => {
            const trimmed = line.trim();
            if (!trimmed) return;
            try {
                const data = JSON.parse(trimmed);
                if (data.ready) {
                    daemonReady = true;
                    console.log('[FACE_DAEMON] Persistent AI Worker ready (30ms inference)');
                    return;
                }
                if (data.id !== undefined && pendingRequests.has(data.id)) {
                    const req = pendingRequests.get(data.id)!;
                    clearTimeout(req.timer);
                    pendingRequests.delete(data.id);
                    req.resolve(data);
                }
            } catch (e) {
                console.warn('[FACE_DAEMON] Bad JSON line:', trimmed);
            }
        });

        child.stderr?.on('data', (d) => {
            const msg = d.toString().trim();
            if (msg.includes('[DAEMON]')) {
                console.log(msg);
            }
        });

        child.on('error', (err) => {
            console.warn('[FACE_DAEMON] Process error:', err);
            cleanupDaemon();
        });

        child.on('exit', () => {
            cleanupDaemon();
        });
    } catch (e) {
        console.warn('[FACE_DAEMON] Could not spawn daemon, using fallback:', e);
    }
}

function cleanupDaemon() {
    daemonProcess = null;
    daemonReady = false;
    for (const [, req] of pendingRequests) {
        clearTimeout(req.timer);
        req.reject(new Error('AI daemon exited'));
    }
    pendingRequests.clear();
}

function toBase64(imageSource: string | Buffer): string {
    if (Buffer.isBuffer(imageSource)) {
        return imageSource.toString('base64');
    }
    const trimmed = imageSource.trim();
    if (trimmed.startsWith('data:image')) {
        return trimmed.split(',')[1] ?? '';
    }
    if (trimmed.length < 260 && existsSync(trimmed)) {
        return readFileSync(trimmed).toString('base64');
    }
    return trimmed;
}

async function callDaemon(action: 'detect' | 'enroll' | 'identify', imageSource: string | Buffer, extra: Record<string, any> = {}): Promise<any> {
    ensureDaemon();
    if (!daemonProcess || !daemonReady) {
        // Fall back to CLI if daemon not ready yet
        return null;
    }

    const b64 = toBase64(imageSource);
    const id = ++reqSeq;
    const payload = JSON.stringify({ id, action, image: b64, ...extra }) + '\n';

    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
            if (pendingRequests.has(id)) {
                pendingRequests.delete(id);
                reject(new Error('AI daemon request timed out'));
            }
        }, 8000);

        pendingRequests.set(id, { resolve, reject, timer });
        try {
            daemonProcess!.stdin!.write(payload);
        } catch (err) {
            clearTimeout(timer);
            pendingRequests.delete(id);
            reject(err);
        }
    });
}

function parseSource(imageSource: string | Buffer): { sourceArgs: string[]; buffer?: Buffer } {
    if (Buffer.isBuffer(imageSource)) {
        return { sourceArgs: ['--source', '-'], buffer: imageSource };
    }
    if (typeof imageSource === 'string') {
        const trimmed = imageSource.trim();
        if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
            return { sourceArgs: ['--source', trimmed] };
        }
        if (trimmed.length < 260 && existsSync(trimmed)) {
            return { sourceArgs: ['--source', trimmed] };
        }
        let b64 = trimmed;
        if (b64.includes(',')) {
            b64 = b64.split(',')[1];
        }
        const buf = Buffer.from(b64, 'base64');
        return { sourceArgs: ['--source', '-'], buffer: buf };
    }
    throw new Error('Invalid imageSource format');
}

export function runFaceEngine(args: string[], stdinBuffer?: Buffer): Promise<any> {
    return new Promise((res, rej) => {
        const child = execFile(
            'python',
            [faceEngineScript, ...args],
            { cwd: root, timeout: 15000, maxBuffer: 10 * 1024 * 1024, windowsHide: true },
            (error, stdout, stderr) => {
                if (error) {
                    try {
                        const parsed = JSON.parse(stdout);
                        return res(parsed);
                    } catch {}
                    return rej(new Error(stderr || error.message));
                }
                try {
                    const parsed = JSON.parse(stdout.trim());
                    res(parsed);
                } catch (parseErr) {
                    rej(new Error(`Failed to parse AI output: ${stdout}\nStderr: ${stderr}`));
                }
            }
        );

        if (stdinBuffer && child.stdin) {
            child.stdin.end(stdinBuffer);
        }
    });
}

export async function enrollFaceReal(
    studentId: string,
    studentCode: string,
    name: string,
    imageSource: string | Buffer
): Promise<FaceEnrollResult> {
    try {
        const res = await callDaemon('enroll', imageSource, { studentId, studentCode, name });
        if (res) return res;
    } catch (e) {
        console.warn('[FACE_SERVICE] Daemon enroll failed, falling back to CLI:', e);
    }
    const { sourceArgs, buffer } = parseSource(imageSource);
    return runFaceEngine(
        ['enroll', ...sourceArgs, '--student-id', studentId, '--student-code', studentCode, '--name', name],
        buffer
    );
}

export async function identifyFaceReal(
    imageSource: string | Buffer
): Promise<FaceIdentifyResult> {
    try {
        const res = await callDaemon('identify', imageSource);
        if (res) return res;
    } catch (e) {
        console.warn('[FACE_SERVICE] Daemon identify failed, falling back to CLI:', e);
    }
    const { sourceArgs, buffer } = parseSource(imageSource);
    return runFaceEngine(['identify', ...sourceArgs], buffer);
}

export async function detectFaceReal(
    imageSource: string | Buffer
): Promise<FaceDetectionResult> {
    try {
        const res = await callDaemon('detect', imageSource);
        if (res) return res;
    } catch (e) {
        console.warn('[FACE_SERVICE] Daemon detect failed, falling back to CLI:', e);
    }
    const { sourceArgs, buffer } = parseSource(imageSource);
    return runFaceEngine(['detect', ...sourceArgs], buffer);
}

// Start daemon eagerly at module load
ensureDaemon();
