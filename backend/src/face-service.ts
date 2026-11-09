import { execFile } from 'node:child_process';
import { resolve } from 'node:path';
import { existsSync } from 'node:fs';

const root = resolve(import.meta.dirname, '../..');
const faceEngineScript = resolve(root, 'ai-service/face_engine.py');

export interface FaceDetectionResult {
    success: boolean;
    faces?: Array<{ box: number[]; score: number }>;
    width?: number;
    height?: number;
    error?: string;
    message?: string;
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
        // Base64 string or data URL: buffer to stdin to avoid Windows CLI length limits
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
    const { sourceArgs, buffer } = parseSource(imageSource);
    return runFaceEngine(
        ['enroll', ...sourceArgs, '--student-id', studentId, '--student-code', studentCode, '--name', name],
        buffer
    );
}

export async function identifyFaceReal(
    imageSource: string | Buffer
): Promise<FaceIdentifyResult> {
    const { sourceArgs, buffer } = parseSource(imageSource);
    return runFaceEngine(['identify', ...sourceArgs], buffer);
}

export async function detectFaceReal(
    imageSource: string | Buffer
): Promise<FaceDetectionResult> {
    const { sourceArgs, buffer } = parseSource(imageSource);
    return runFaceEngine(['detect', ...sourceArgs], buffer);
}
