/* global axios */
import ApiClient from './ApiClient';

class KanbanConfigAPI extends ApiClient {
  constructor() {
    super('kanban_config', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  create(configData) {
    return axios.post(this.url, configData);
  }

  update(configData) {
    return axios.patch(this.url, configData);
  }

  delete() {
    return axios.delete(this.url);
  }

  testWebhook() {
    return axios.post(`${this.url}/test_webhook`);
  }
}

export default new KanbanConfigAPI();
