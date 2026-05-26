import type { AuthState, BroadcastFn } from './types';

export class AuthManager {
  _state: string = 'initializing';
  _resolve: ((value: string) => void) | null = null;
  _hint: string | null = null;
  _error: string | null = null;
  _broadcast: BroadcastFn | undefined;

  constructor(broadcast?: BroadcastFn) {
    this._broadcast = broadcast;
  }

  setBroadcast(fn: BroadcastFn | undefined) {
    this._broadcast = fn;
  }

  getState(): AuthState {
    return {
      state: this._state,
      hint: this._hint,
      error: this._error,
      canInput: this._resolve !== null,
    };
  }

  async submitInput(value: string): Promise<boolean> {
    if (this._resolve) {
      const resolve = this._resolve;
      this._resolve = null;
      resolve(value);
      return true;
    }
    return false;
  }

  getPhoneNumber = async (retry: boolean): Promise<string> => {
    this._state = 'waitPhone';
    this._error = retry ? 'Invalid phone number, please re-enter' : null;
    if (typeof this._broadcast === 'function') {
      this._broadcast({ event: 'authNeeded', type: 'phoneNumber', retry });
    }
    return new Promise<string>((resolve) => {
      this._resolve = resolve;
    });
  };

  getAuthCode = async (retry: boolean): Promise<string> => {
    this._state = 'waitCode';
    this._error = retry ? 'Invalid code, please re-enter' : null;
    if (typeof this._broadcast === 'function') {
      this._broadcast({ event: 'authNeeded', type: 'authCode', retry });
    }
    return new Promise<string>((resolve) => {
      this._resolve = resolve;
    });
  };

  getPassword = async (hint: string, retry: boolean): Promise<string> => {
    this._state = 'waitPassword';
    this._hint = hint || null;
    this._error = retry ? 'Wrong password, please re-enter' : null;
    if (typeof this._broadcast === 'function') {
      this._broadcast({ event: 'authNeeded', type: 'password', hint, retry });
    }
    return new Promise<string>((resolve) => {
      this._resolve = resolve;
    });
  };

  markReady() {
    this._state = 'ready';
  }

  markError(msg: string) {
    this._state = 'error';
    this._error = msg;
  }
}
