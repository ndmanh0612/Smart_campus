import { id, reject, str } from './platform.ts';
export type ProviderContext = {
    eventId: string;
    deviceId: string;
    timestamp: string;
};
export type VisionInput = ProviderContext & {
    captureRef: string | null;
};
export type FaceInput = VisionInput & {
    allowedStudentIds: readonly string[];
    purpose: string;
};
const correlation = (context: ProviderContext) => ({ eventId: context.eventId, deviceId: context.deviceId, timestamp: context.timestamp });
export type CaptureResult = ProviderContext & {
    schemaVersion: 1;
    captureId: string;
    evidenceRef: string | null;
    source: 'DEMO' | 'REAL';
};
export type LivenessResult = ProviderContext & {
    source: 'DEMO' | 'REAL';
    status: 'PASS' | 'FAIL' | 'UNKNOWN';
    confidence: number | null;
};
export type FaceResult = ProviderContext & {
    schemaVersion: 1;
    identity: {
        studentId: string;
    } | null;
    confidence: number | null;
    livenessStatus: LivenessResult['status'];
    source: 'DEMO' | 'REAL';
    recognitionStatus: 'MATCH' | 'NO_MATCH' | 'LOW_CONFIDENCE' | 'ERROR';
    evidenceRef: string | null;
    modelVersion: string;
};
export type OcrResult = ProviderContext & {
    schemaVersion: 1;
    rawText: string | null;
    normalizedPlate: string | null;
    confidence: number | null;
    evidenceRef: string | null;
    source: 'DEMO' | 'REAL';
    recognitionStatus: 'READ' | 'UNREADABLE' | 'LOW_CONFIDENCE' | 'ERROR';
    normalizationVersion: string;
};
export interface CameraCaptureProvider {
    capture(context: ProviderContext): Promise<CaptureResult>;
}
export interface LivenessProvider {
    evaluate(context: VisionInput): Promise<LivenessResult>;
}
export interface FaceRecognitionProvider {
    recognize(context: FaceInput): Promise<FaceResult>;
}
export interface LicensePlateRecognitionProvider {
    recognize(context: VisionInput): Promise<OcrResult>;
}
export interface GateControllerProvider {
    execute(command: {
        id: string;
        expires_at: Date;
    }): {
        status: 'OPENED' | 'FAILED' | 'UNKNOWN';
        source: 'SIMULATOR';
    };
}
export class DemoCameraProvider implements CameraCaptureProvider {
    async capture(context: ProviderContext): Promise<CaptureResult> { return { ...correlation(context), schemaVersion: 1, captureId: id(), evidenceRef: null, source: 'DEMO' }; }
}
export class DemoLivenessProvider implements LivenessProvider {
    readonly scenario: string;
    constructor(scenario: string) { this.scenario = scenario; }
    async evaluate(context: VisionInput): Promise<LivenessResult> { const scenario = this.scenario; return { ...correlation(context), source: 'DEMO', status: scenario === 'LIVENESS_FAIL' ? 'FAIL' : scenario === 'TIMEOUT' ? 'UNKNOWN' : 'PASS', confidence: scenario === 'TIMEOUT' ? null : 0.99 }; }
}
export class DemoFaceProvider implements FaceRecognitionProvider {
    readonly studentId: string;
    readonly scenario: string;
    constructor(options: {
        studentId: string;
        scenario: string;
    }) { this.studentId = options.studentId; this.scenario = options.scenario; }
    async recognize(context: FaceInput): Promise<FaceResult> {
        const { studentId, scenario } = this;
        if (!context.allowedStudentIds.includes(studentId))
            reject(422, 'PROVIDER_SCOPE_MISMATCH', 'Identity không thuộc phạm vi nhận diện được cấp.');
        if (!['SUCCESS', 'UNKNOWN', 'LOW_CONFIDENCE', 'LIVENESS_FAIL', 'MULTIPLE_FACES', 'TIMEOUT'].includes(scenario))
            reject(400, 'INVALID_SCENARIO', 'Tình huống khuôn mặt không hợp lệ.');
        const live = await new DemoLivenessProvider(scenario).evaluate(context);
        const match = ['SUCCESS', 'LIVENESS_FAIL'].includes(scenario);
        return { ...correlation(context), schemaVersion: 1, identity: match ? { studentId } : null, confidence: scenario === 'TIMEOUT' ? null : scenario === 'LOW_CONFIDENCE' ? 0.35 : 0.98, livenessStatus: live.status, source: 'DEMO', recognitionStatus: match ? 'MATCH' : scenario === 'LOW_CONFIDENCE' ? 'LOW_CONFIDENCE' : scenario === 'TIMEOUT' ? 'ERROR' : 'NO_MATCH', evidenceRef: null, modelVersion: 'demo-v1' };
    }
}
export function normalizePlate(value: string) {
    const s = str(value, 30).toUpperCase().replace(/[\s.\-]/g, '');
    if (!/^[0-9]{2}[A-Z]{1,2}[0-9]{4,6}$/.test(s))
        reject(422, 'INVALID_PLATE', 'Biển số demo không đúng định dạng được hỗ trợ.');
    return s;
}
export class DemoOCRProvider implements LicensePlateRecognitionProvider {
    readonly rawText: string;
    readonly scenario: string;
    constructor(options: {
        rawText: string;
        scenario: string;
    }) { this.rawText = options.rawText; this.scenario = options.scenario; }
    async recognize(context: VisionInput): Promise<OcrResult> {
        const { rawText, scenario } = this;
        if (!['SUCCESS', 'LOW_CONFIDENCE', 'UNREADABLE', 'TIMEOUT'].includes(scenario))
            reject(400, 'INVALID_SCENARIO', 'Tình huống OCR không hợp lệ.');
        const read = ['SUCCESS', 'LOW_CONFIDENCE'].includes(scenario);
        return { ...correlation(context), schemaVersion: 1, rawText: read ? rawText : null, normalizedPlate: read ? normalizePlate(rawText) : null, confidence: read ? (scenario === 'SUCCESS' ? 0.95 : 0.3) : null, evidenceRef: null, source: 'DEMO', recognitionStatus: scenario === 'SUCCESS' ? 'READ' : scenario === 'LOW_CONFIDENCE' ? 'LOW_CONFIDENCE' : scenario === 'UNREADABLE' ? 'UNREADABLE' : 'ERROR', normalizationVersion: 'vn-plate-v1' };
    }
}
export class SimulatedGateProvider implements GateControllerProvider {
    execute(command: {
        id: string;
        expires_at: Date;
    }): {
        status: 'OPENED' | 'FAILED' | 'UNKNOWN';
        source: 'SIMULATOR';
    } { return { status: new Date(command.expires_at) < new Date() ? 'FAILED' : 'OPENED', source: 'SIMULATOR' }; }
}
