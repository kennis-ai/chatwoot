/* global axios */
import ApiClient from './ApiClient';

class OffersAPI extends ApiClient {
  constructor() {
    super('offers', { accountScoped: true });
  }

  getOffers(params) {
    return axios.get(`${this.url}`, { params });
  }

  getOffer(id) {
    return axios.get(`${this.url}/${id}`);
  }

  createOffer(data) {
    return axios.post(this.url, data);
  }

  updateOffer(id, data) {
    return axios.patch(`${this.url}/${id}`, data);
  }

  deleteOffer(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new OffersAPI();
