import FunnelAPI from '../../api/funnel';

const state = {
  funnels: [],
  selectedFunnel: null,
  loading: false,
  error: null,
};

const getters = {
  getFunnels: state => state.funnels,
  getActiveFunnels: state => state.funnels.filter(f => f.active),
  getSelectedFunnel: state => state.selectedFunnel,
  getFunnelById: state => id =>
    state.funnels.find(f => f.id === parseInt(id, 10)),
  isLoading: state => state.loading,
  getError: state => state.error,
};

const actions = {
  async fetchFunnels({ commit }) {
    commit('SET_LOADING', true);
    try {
      const response = await FunnelAPI.getFunnels();
      const funnels = response.data;
      commit('SET_FUNNELS', funnels);

      // Auto-select first active funnel if none selected
      if (!state.selectedFunnel && funnels.length > 0) {
        const firstActive = funnels.find(f => f.active) || funnels[0];
        commit('SET_SELECTED_FUNNEL', firstActive);
      }

      return funnels;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    } finally {
      commit('SET_LOADING', false);
    }
  },

  async fetchFunnel({ commit }, id) {
    try {
      const response = await FunnelAPI.getFunnel(id);
      commit('UPDATE_FUNNEL', response.data);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async createFunnel({ commit }, funnelData) {
    try {
      const response = await FunnelAPI.createFunnel(funnelData);
      commit('ADD_FUNNEL', response.data);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async updateFunnel({ commit }, { id, data }) {
    try {
      const response = await FunnelAPI.updateFunnel(id, data);
      commit('UPDATE_FUNNEL', response.data);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async deleteFunnel({ commit }, id) {
    try {
      await FunnelAPI.deleteFunnel(id);
      commit('REMOVE_FUNNEL', id);
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async getStageStats({ commit }, id) {
    try {
      const response = await FunnelAPI.getStageStats(id);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  async getKanbanItems({ commit }, id) {
    try {
      const response = await FunnelAPI.getKanbanItems(id);
      return response.data;
    } catch (error) {
      commit('SET_ERROR', error);
      throw error;
    }
  },

  setSelectedFunnel({ commit }, funnel) {
    commit('SET_SELECTED_FUNNEL', funnel);
  },

  clearSelectedFunnel({ commit }) {
    commit('SET_SELECTED_FUNNEL', null);
  },
};

const mutations = {
  SET_FUNNELS(state, funnels) {
    state.funnels = funnels;
  },

  ADD_FUNNEL(state, funnel) {
    state.funnels.push(funnel);
  },

  UPDATE_FUNNEL(state, updatedFunnel) {
    const index = state.funnels.findIndex(f => f.id === updatedFunnel.id);
    if (index !== -1) {
      state.funnels.splice(index, 1, updatedFunnel);
    }
    // Update selected if it's the same one
    if (state.selectedFunnel?.id === updatedFunnel.id) {
      state.selectedFunnel = updatedFunnel;
    }
  },

  REMOVE_FUNNEL(state, id) {
    state.funnels = state.funnels.filter(f => f.id !== id);
    // Clear or switch selected funnel if it was deleted
    if (state.selectedFunnel?.id === id) {
      const activeFunnels = state.funnels.filter(f => f.active);
      state.selectedFunnel = activeFunnels[0] || state.funnels[0] || null;
    }
  },

  SET_SELECTED_FUNNEL(state, funnel) {
    state.selectedFunnel = funnel;
  },

  SET_LOADING(state, loading) {
    state.loading = loading;
  },

  SET_ERROR(state, error) {
    state.error = error;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
