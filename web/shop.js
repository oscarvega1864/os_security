(() => {
  'use strict';
  // Tienda Gruppe Sechs: catalogo por categorias, cantidades, carrito, forma de pago y resultado.
  // Solo interfaz: precios, permisos (productos de personal G6) y saldo los valida el servidor.
  const root = document.getElementById('shop');
  if (!root) return;
  const resource = () => typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'os_security';
  const el = (tag, value, className) => { const node = document.createElement(tag); if (value != null) node.textContent = String(value); if (className) node.className = className; return node; };
  // Miles con punto siempre ($1.240, $5.000.302), como el HUD de dinero.
  const money = value => `$${String(Math.round(Number(value) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, '.')}`;
  let state = null;

  function post(endpoint, body) {
    return fetch(`https://${resource()}/${endpoint}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body) }).catch(() => {});
  }
  function close() { if (!state) return; state = null; root.hidden = true; root.replaceChildren(); post('shopClose', {}); }
  function button(title, action, disabled = false, className) {
    const node = el('button', title, className); node.type = 'button'; node.disabled = disabled;
    node.addEventListener('click', () => { if (!node.disabled) action(); }); return node;
  }
  const total = () => state.data.products.reduce((sum, product) => sum + (state.cart[product.item] || 0) * product.price, 0);
  const units = () => Object.values(state.cart).reduce((sum, value) => sum + value, 0);

  function render() {
    const { data, text } = state;
    root.replaceChildren();
    const panel = el('section', null, 'shop-panel');
    const head = el('header', null, 'shop-head');
    const brand = el('div', null, 'shop-brand'); brand.append(el('span', 'G6', 'shop-mono'));
    const titles = el('div'); titles.append(el('span', data.location, 'shop-overline'), el('h2', text.title));
    brand.append(titles);
    head.append(brand, button(text.close, close, false, 'shop-close'));
    panel.append(head);
    const body = el('div', null, 'shop-body');
    // Catalogo por categorias.
    const catalog = el('div', null, 'shop-catalog');
    const order = ['tablet', 'kit', 'tool', 'material', 'access'];
    const groups = new Map();
    for (const product of data.products) {
      const key = order.includes(product.category) ? product.category : 'other';
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(product);
    }
    for (const key of [...order, 'other']) {
      const list = groups.get(key); if (!list) continue;
      catalog.append(el('h3', text.categories?.[key] || key, 'shop-category'));
      const grid = el('div', null, 'shop-grid');
      for (const product of list) {
        const card = el('article', null, `shop-card${product.allowed ? '' : ' locked'}`);
        card.append(el('span', null, `shop-icon icon-${key}`));
        const info = el('div', null, 'shop-info');
        info.append(el('strong', product.name.replace(/^Gruppe Sechs · /, '')), el('span', money(product.price), 'shop-price'));
        if (product.staff) info.append(el('span', product.allowed ? text.staffItem : text.staffOnly, 'shop-tag'));
        card.append(info);
        const qty = state.cart[product.item] || 0;
        const stepper = el('div', null, 'shop-stepper');
        const set = value => { const next = Math.max(0, Math.min(data.maxQuantity, value)); if (next) state.cart[product.item] = next; else delete state.cart[product.item]; render(); };
        stepper.append(button('−', () => set(qty - 1), !product.allowed || qty === 0), el('span', qty, 'shop-qty'),
          button('+', () => set(qty + 1), !product.allowed || qty >= data.maxQuantity));
        card.append(stepper);
        grid.append(card);
      }
      catalog.append(grid);
    }
    body.append(catalog);
    // Resumen y pago.
    const side = el('aside', null, 'shop-side');
    side.append(el('span', text.cart, 'shop-overline'));
    const lines = el('div', null, 'shop-lines');
    for (const product of data.products) {
      const qty = state.cart[product.item]; if (!qty) continue;
      const line = el('div', null, 'shop-line');
      line.append(el('span', `${qty} × ${product.name.replace(/^Gruppe Sechs · /, '')}`), el('strong', money(qty * product.price)));
      lines.append(line);
    }
    if (!units()) lines.append(el('p', text.empty, 'shop-muted'));
    side.append(lines);
    const sum = el('div', null, 'shop-total'); sum.append(el('span', text.total), el('strong', money(total())));
    side.append(sum);
    const accounts = el('div', null, 'shop-accounts');
    for (const account of data.accounts) {
      const balance = data.balance ? data.balance[account] : null;
      const option = button(`${text.accounts?.[account] || account}${balance != null ? ' · ' + money(balance) : ''}`, () => { state.account = account; render(); }, false,
        `shop-account${state.account === account ? ' selected' : ''}`);
      accounts.append(option);
    }
    side.append(el('span', text.pay, 'shop-overline'), accounts);
    const balance = data.balance ? data.balance[state.account] : null;
    const short = balance != null && total() > balance;
    if (short) side.append(el('p', text.insufficient, 'shop-warning'));
    side.append(button(state.busy ? text.paying : `${text.buy} · ${money(total())}`, buy, state.busy || !units() || short, 'shop-buy'));
    if (state.message) side.append(el('p', state.message.text, `shop-message ${state.message.ok ? 'ok' : 'error'}`));
    if (!data.staff) side.append(el('p', text.staffHint, 'shop-muted'));
    body.append(side);
    panel.append(body);
    root.append(panel);
  }
  function buy() {
    if (!state || state.busy || !units()) return;
    state.busy = true; state.message = null; render();
    const cart = Object.entries(state.cart).map(([item, amount]) => ({ item, amount }));
    post('shopBuy', { cart, account: state.account });
  }

  window.addEventListener('message', event => {
    const message = event.data;
    if (message?.type === 'shop' && message.data && message.text) {
      state = { data: message.data, text: message.text, cart: {}, account: message.data.accounts?.[0] || 'bank', busy: false, message: null };
      root.hidden = false; render();
    } else if (message?.type === 'shopResult' && state) {
      state.busy = false;
      if (message.ok && message.data) {
        state.cart = {};
        if (message.data.balance) state.data.balance = message.data.balance;
        state.message = { ok: !message.data.partial, text: message.data.message };
      } else state.message = { ok: false, text: String(message.data || state.text.failed) };
      render();
    } else if (message?.type === 'shopClose') { state = null; root.hidden = true; root.replaceChildren(); }
  });
  window.addEventListener('keydown', event => { if (event.key === 'Escape' && state) close(); });
})();
