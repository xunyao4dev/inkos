import { pathToFileURL } from 'node:url';
export const import_meta_url = typeof __filename !== 'undefined' ? pathToFileURL(__filename).href : "file:///";
