/* global axios */
import ApiClient from './ApiClient';

class FunnelAPI extends ApiClient {
  constructor() {
    super('funnels', { accountScoped: true });
  }

  getFunnels() {
    return axios.get(this.url);
  }

  getFunnel(id) {
    return axios.get(`${this.url}/${id}`);
  }

  createFunnel(data) {
    return axios.post(this.url, { funnel: data });
  }

  updateFunnel(id, data) {
    return axios.patch(`${this.url}/${id}`, { funnel: data });
  }

  deleteFunnel(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  getStageStats(id) {
    return axios.get(`${this.url}/${id}/stage_stats`);
  }

  getKanbanItems(id) {
    return axios.get(`${this.url}/${id}/kanban_items`);
  }
}

export default new FunnelAPI();
