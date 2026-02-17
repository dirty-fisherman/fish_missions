import type { RootConfig } from './types';
import { LoadJsonFile } from 'utils';

let config = LoadJsonFile('static/config.json');

$BROWSER: {
  config = await config;
}

export default config as RootConfig;
