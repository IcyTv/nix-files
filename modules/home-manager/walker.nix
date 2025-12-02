{...}: {
  programs.walker = {
    enable = true;
    runAsService = true;

    config = {
      theme = "catppuccin-mocha";
    };

    themes.catppuccin-mocha = {
      style = ''
        window {
            background-color: rgba(30, 30, 45, 0.95);
            border: 2px solid #cba6f7;
        }

        box#main {
            margin: 10px;
        }

        box#input-box {
            background-color: #181825;
            border-radius: 10px;
            padding: 5px;
            border: 1px solid #313244;
        }

        entry {
            background-color: transparent;
            color: #cdd6f4;
            caret-color: #f5e0dc;
        }

        list {
            margin-top: 10px;
        }

        row {
            border-radius: 10px;
            padding: 10px;
        }

        row:selected {
            background-color: #45475a;
        }
      '';
      layouts = {
        "item" = ''
          <item>
              <box spacing="10">
           <box>
               <icon name="icon" size="32"/>
           </box>
           <box orientation="vertical">
               <text name="name" color="#cdd6f4" font="bold"/>
               <text name="description" color="#a6adc8"/>
           </box>
              </box>
          </item>
        '';
      };
    };
  };
}
