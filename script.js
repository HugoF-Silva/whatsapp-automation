import http from 'k6/http';
import { sleep } from 'k6';

export let options = {
  vus: 4000,
  duration: '10m',
};

export default function () {
  http.get('https://your-app-url.com/');
  sleep(1);
}
