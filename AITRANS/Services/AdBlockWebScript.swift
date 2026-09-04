import Foundation

enum AdBlockWebScript {
    static let contentWorldName = "AITRANS.AdBlock"
    static let elementRuleMessageName = "aitransAdBlockElementRule"

    static func bootstrap(
        preferences: AdBlockPreferences,
        rememberedSelectors: [String]
    ) -> String {
        let payload = configurationJSON(
            preferences: preferences,
            rememberedSelectors: rememberedSelectors
        )
        return """
        (() => {
          const incoming = \(payload);
          if (globalThis.__aitransAdBlockRuntime) {
            globalThis.__aitransAdBlockRuntime.apply(incoming);
            return;
          }

          const state = {
            config: incoming,
            manualHidden: new Map(),
            antiBlockHidden: new Map(),
            mediaGestureAt: new WeakMap(),
            copyStyle: null,
            bodyOverflow: null,
            scheduled: false
          };
          const separatorCharacter = String.fromCharCode(10);
          const blockerText = /(ad[\\s_-]*block|广告拦截|关闭.{0,8}广告|disable.{0,12}ad[\\s_-]*block|whitelist|白名单)/i;
          const blockerSelector = 'dialog,[role="dialog"],[class*="adblock" i],[id*="adblock" i],[class*="ad-block" i],[id*="ad-block" i],[class*="blocker" i],[id*="blocker" i]';

          const rememberStyle = (element, ledger) => {
            if (ledger.has(element)) return;
            ledger.set(element, {
              display: element.style.getPropertyValue('display'),
              displayPriority: element.style.getPropertyPriority('display'),
              visibility: element.style.getPropertyValue('visibility'),
              visibilityPriority: element.style.getPropertyPriority('visibility'),
              pointerEvents: element.style.getPropertyValue('pointer-events'),
              pointerPriority: element.style.getPropertyPriority('pointer-events')
            });
          };
          const hideElement = (element, ledger) => {
            if (!element || element === document.documentElement || element === document.body) return;
            rememberStyle(element, ledger);
            element.style.setProperty('display', 'none', 'important');
            element.style.setProperty('visibility', 'hidden', 'important');
            element.style.setProperty('pointer-events', 'none', 'important');
          };
          const restoreElement = (element, saved) => {
            if (!element || !saved) return;
            const restore = (name, value, priority) => {
              if (value) element.style.setProperty(name, value, priority || '');
              else element.style.removeProperty(name);
            };
            restore('display', saved.display, saved.displayPriority);
            restore('visibility', saved.visibility, saved.visibilityPriority);
            restore('pointer-events', saved.pointerEvents, saved.pointerPriority);
          };
          const reconcileLedger = (ledger, wanted) => {
            for (const [element, saved] of ledger) {
              if (!element.isConnected || !wanted.has(element)) {
                restoreElement(element, saved);
                ledger.delete(element);
              }
            }
            for (const element of wanted) hideElement(element, ledger);
          };

          const installCopyStyle = () => {
            if (!state.config.script) {
              if (state.copyStyle) state.copyStyle.remove();
              state.copyStyle = null;
              return;
            }
            if (state.copyStyle && state.copyStyle.isConnected) return;
            const style = document.createElement('style');
            style.setAttribute('data-aitrans-copy-unlock', '1');
            style.textContent = 'html,body{user-select:text!important;-webkit-user-select:text!important;-webkit-touch-callout:default!important}body :not(input):not(textarea):not(select):not(button){user-select:text!important;-webkit-user-select:text!important;-webkit-touch-callout:default!important}';
            (document.head || document.documentElement)?.appendChild(style);
            state.copyStyle = style;
          };

          const normalizeMedia = (root) => {
            if (!state.config.script) return;
            const media = [];
            if (root && root.matches && root.matches('video,audio')) media.push(root);
            if (root && root.querySelectorAll) media.push(...root.querySelectorAll('video,audio'));
            media.slice(0, 80).forEach(element => {
              element.autoplay = false;
              element.removeAttribute('autoplay');
              if (element.tagName === 'VIDEO') {
                element.playsInline = true;
                element.setAttribute('playsinline', '');
                element.setAttribute('webkit-playsinline', '');
              }
            });
          };

          const selectorFor = (element) => {
            if (!element || !element.tagName) return '';
            const escape = value => globalThis.CSS && CSS.escape
              ? CSS.escape(value)
              : value.replace(/[^a-zA-Z0-9_-]/g, character => '\\' + character);
            const parts = [];
            let node = element;
            while (node && node.nodeType === 1 && parts.length < 6) {
              if (node === document.documentElement || node === document.body) break;
              let part = node.tagName.toLowerCase();
              if (node.id) {
                part += '#' + escape(node.id);
                parts.unshift(part);
                break;
              }
              if (node.parentElement) {
                const siblings = Array.from(node.parentElement.children)
                  .filter(candidate => candidate.tagName === node.tagName);
                if (siblings.length > 1) {
                  part += ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')';
                }
              }
              parts.unshift(part);
              node = node.parentElement;
            }
            return parts.join('>').slice(0, 300);
          };

          const rememberedForCurrentHost = () => {
            const host = location.hostname.toLowerCase();
            if (!host) return [];
            return (Array.isArray(state.config.selectors) ? state.config.selectors : [])
              .slice(0, 32)
              .flatMap(entry => {
                if (typeof entry !== 'string') return [];
                const separator = entry.indexOf(separatorCharacter);
                if (separator <= 0 || entry.slice(0, separator).toLowerCase() !== host) return [];
                const selector = entry.slice(separator + 1);
                return selector && selector.length <= 300 ? [selector] : [];
              });
          };

          const applyRememberedSelectors = () => {
            const wanted = new Set();
            if (state.config.picker) {
              rememberedForCurrentHost().forEach(selector => {
                try {
                  document.querySelectorAll(selector).forEach(element => {
                    if (element !== document.documentElement && element !== document.body
                        && element.tagName !== 'MAIN' && element.tagName !== 'ARTICLE') {
                      wanted.add(element);
                    }
                  });
                } catch (_) {}
              });
            }
            reconcileLedger(state.manualHidden, wanted);
          };

          const scanAntiBlockers = () => {
            const wanted = new Set();
            if (state.config.script) {
              let candidates = [];
              try { candidates = Array.from(document.querySelectorAll(blockerSelector)).slice(0, 80); } catch (_) {}
              const viewportArea = Math.max(1, innerWidth * innerHeight);
              candidates.forEach(element => {
                if (element === document.documentElement || element === document.body
                    || element.tagName === 'MAIN' || element.tagName === 'ARTICLE') return;
                const text = (element.innerText || element.textContent || '').trim().slice(0, 600);
                if (text.length < 4 || !blockerText.test(text)) return;
                const rect = element.getBoundingClientRect();
                const style = getComputedStyle(element);
                const areaRatio = Math.max(0, rect.width) * Math.max(0, rect.height) / viewportArea;
                const elevated = (style.position === 'fixed' || style.position === 'sticky')
                  && Number.parseInt(style.zIndex || '0', 10) >= 100;
                if (areaRatio >= 0.25 || elevated || element.tagName === 'DIALOG') wanted.add(element);
              });
            }
            reconcileLedger(state.antiBlockHidden, wanted);
            const hasHiddenBlocker = state.antiBlockHidden.size > 0;
            if (hasHiddenBlocker && document.body) {
              if (state.bodyOverflow === null) state.bodyOverflow = document.body.style.overflow;
              document.body.style.setProperty('overflow', 'auto', 'important');
            } else if (state.bodyOverflow !== null && document.body) {
              if (state.bodyOverflow) document.body.style.overflow = state.bodyOverflow;
              else document.body.style.removeProperty('overflow');
              state.bodyOverflow = null;
            }
          };

          const apply = () => {
            installCopyStyle();
            normalizeMedia(document);
            applyRememberedSelectors();
            scanAntiBlockers();
          };
          const scheduleApply = () => {
            if (state.scheduled) return;
            state.scheduled = true;
            setTimeout(() => {
              state.scheduled = false;
              apply();
            }, 80);
          };

          ['contextmenu', 'selectstart', 'copy', 'cut'].forEach(type => {
            document.addEventListener(type, event => {
              if (state.config.script) event.stopImmediatePropagation();
            }, true);
          });
          document.addEventListener('pointerdown', event => {
            const media = event.target && event.target.closest
              ? event.target.closest('video,audio')
              : null;
            if (media) state.mediaGestureAt.set(media, Date.now());
          }, true);
          document.addEventListener('play', event => {
            if (!state.config.script) return;
            const media = event.target;
            const gestureAt = state.mediaGestureAt.get(media) || 0;
            if (Date.now() - gestureAt > 1800 && media && media.pause) media.pause();
          }, true);
          document.addEventListener('webkitbeginfullscreen', event => {
            if (!state.config.script) return;
            const media = event.target;
            if (media && media.pause) media.pause();
            if (media && media.webkitExitFullscreen) {
              try { media.webkitExitFullscreen(); } catch (_) {}
            }
          }, true);
          document.addEventListener('fullscreenchange', () => {
            if (!state.config.script || !document.fullscreenElement) return;
            const media = document.fullscreenElement;
            if (media.pause) media.pause();
            if (document.exitFullscreen) document.exitFullscreen().catch(() => {});
          }, true);
          document.addEventListener('click', event => {
            if (!state.config.picker) return;
            const target = event.target && event.target.closest ? event.target.closest('*') : null;
            if (!target || target === document.documentElement || target === document.body
                || target.tagName === 'MAIN' || target.tagName === 'ARTICLE') return;
            const selector = selectorFor(target);
            if (!selector) return;
            event.preventDefault();
            event.stopImmediatePropagation();
            hideElement(target, state.manualHidden);
            const bridge = globalThis.webkit && globalThis.webkit.messageHandlers
              ? globalThis.webkit.messageHandlers.\(elementRuleMessageName)
              : null;
            if (bridge) bridge.postMessage(selector);
          }, true);

          const root = document.documentElement;
          if (root) {
            new MutationObserver(records => {
              records.forEach(record => record.addedNodes.forEach(node => normalizeMedia(node)));
              scheduleApply();
            }).observe(root, {
              childList: true,
              subtree: true,
              attributes: true,
              attributeFilter: ['class', 'id', 'style', 'hidden', 'autoplay']
            });
          }

          globalThis.__aitransAdBlockRuntime = {
            apply(next) {
              if (!next || typeof next !== 'object') return;
              state.config = {
                script: next.script === true,
                picker: next.picker === true,
                selectors: Array.isArray(next.selectors) ? next.selectors.slice(0, 32) : []
              };
              apply();
            }
          };
          apply();
        })();
        """
    }

    static func runtimeUpdate(
        preferences: AdBlockPreferences,
        rememberedSelectors: [String]
    ) -> String {
        let payload = configurationJSON(
            preferences: preferences,
            rememberedSelectors: rememberedSelectors
        )
        return """
        (() => {
          if (globalThis.__aitransAdBlockRuntime) {
            globalThis.__aitransAdBlockRuntime.apply(\(payload));
          }
        })();
        """
    }

    private static func configurationJSON(
        preferences: AdBlockPreferences,
        rememberedSelectors: [String]
    ) -> String {
        let object: [String: Any] = [
            "script": preferences.effectiveScriptProtection,
            "picker": preferences.effectiveElementPicker,
            "selectors": Array(rememberedSelectors.prefix(32))
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        ), let json = String(data: data, encoding: .utf8) else {
            return #"{"picker":false,"script":false,"selectors":[]}"#
        }
        return json
    }
}
