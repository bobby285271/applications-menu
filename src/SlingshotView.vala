// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
//  
//  Copyright (C) 2011 Giulio Collura
// 
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
// 
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
// 
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

using Gtk;
using Gdk;
using Gee;
using Cairo;
using Granite.Widgets;
using GMenu;

using Slingshot.Widgets;
using Slingshot.Backend;

namespace Slingshot {

    public enum Modality {
        NORMAL_VIEW = 0,
        CATEGORY_VIEW = 1,
        SEARCH_VIEW
    }

    public class SlingshotView : Gtk.Window, Gtk.Buildable {

        public SearchBar searchbar;
        public Widgets.Grid grid;
        public Layout pages = null;
        public Switcher page_switcher;
        public ModeButton view_selector;
        public HBox bottom;

        public SearchView search_view;
        public CategoryView category_view;

        private VBox container;

        public AppSystem app_system;
        private ArrayList<TreeDirectory> categories;
        public HashMap<string, ArrayList<App>> apps;
        private ArrayList<App> filtered;

        private int current_position = 0;
        private int search_view_position = 0;
        private Modality modality;
        public int columns {
            get {
                return grid.get_page_columns ();
            }
        }

        private BackgroundColor bg_color;

        public SlingshotView (Slingshot app) {

            // Window properties
            this.title = "Slingshot";
            this.skip_pager_hint = true;
            this.skip_taskbar_hint = true;
            this.set_type_hint (Gdk.WindowTypeHint.NORMAL);
            this.set_keep_above (true);
            this.decorated = false;

            // No time to have slingshot resizable.
            this.resizable = false;
            this.app_paintable = true;

            // Have the window in the right place
            this.move (5, 27); 
            set_size_request (700, 580);
            read_settings ();

            set_visual (get_screen ().get_rgba_visual());
            get_style_context ().add_provider_for_screen (get_screen (), Slingshot.style_provider, 600);
            Slingshot.icon_theme = IconTheme.get_default ();

            app_system = new AppSystem ();

            categories = app_system.get_categories ();
            app_system.get_apps.begin ((obj, res) => {
                apps = app_system.get_apps.end (res);
                setup_ui ();
                connect_signals ();
                if (!app.silent)
                    show_all ();
            });
            debug ("Apps loaded");

            filtered = new ArrayList<App> ();

        }

        private void setup_ui () {

            debug ("In setup_ui ()");

            // Create the base container
            container = new VBox (false, 0);

            // Add top bar
            var top = new HBox (false, 10);

            view_selector = new ModeButton ();
            view_selector.append (new Image.from_icon_name ("view-list-icons-symbolic", IconSize.MENU));
            view_selector.append (new Image.from_icon_name ("view-list-filter-symbolic", IconSize.MENU));
            view_selector.selected = 0;

            searchbar = new SearchBar ("");
            searchbar.width_request = 250;

            if (Slingshot.settings.show_category_filter) {
                top.pack_start (view_selector, false, false, 0);
            }
            top.pack_end (searchbar, false, false, 0);

            // Create the layout which works like pages
            pages = new Layout (null, null);
            
            // Get the current size of the view
            int width, height;
            get_size (out width, out height);
            
            // Create the "NORMAL_VIEW"
            grid = new Widgets.Grid (height / 180, width / 128);
            pages.put (grid, 0, 0);

            // Create the "SEARCH_VIEW"
            search_view = new SearchView ();
            foreach (ArrayList<App> app_list in apps.values) {
                search_view.add_apps (app_list);
            }
            pages.put (search_view, -columns*130, 0);

            // Create the "CATEGORY_VIEW"
            category_view = new CategoryView (this);
            pages.put (category_view, -columns*130, 0);

            // Create the page switcher
            page_switcher = new Switcher ();

            // A bottom widget to keep the page switcher center
            bottom = new HBox (false, 0);
            bottom.pack_start (new Label (""), true, true, 0); // A fake label 
            bottom.pack_start (page_switcher, false, false, 10);
            bottom.pack_start (new Label (""), true, true, 0); // A fake label

            container.pack_start (top, false, true, 15);
            container.pack_start (Utils.set_padding (pages, 0, 10, 24, 10), true, true, 0);
            container.pack_start (Utils.set_padding (bottom, 0, 9, 15, 9), false, false, 0);
            this.add (Utils.set_padding (container, 15, 15, 1, 15));

            set_modality (Modality.NORMAL_VIEW);
            debug ("Ui setup completed");

        }

        private void connect_signals () {
            
            this.focus_out_event.connect ( () => {
                this.hide_slingshot();
                return false; 
            });

            this.draw.connect (this.draw_background);
            pages.draw.connect (this.draw_pages_background);
            
            searchbar.changed.connect_after (this.search);
            searchbar.grab_focus ();
            search_view.app_launched.connect (hide_slingshot);

            // This function must be after creating the page switcher
            grid.new_page.connect (page_switcher.append);
            populate_grid ();

            page_switcher.active_changed.connect (() => {

                if (page_switcher.active > page_switcher.old_active)
                    this.page_right (page_switcher.active - page_switcher.old_active);
                else
                    this.page_left (page_switcher.old_active - page_switcher.active);

            });

            view_selector.mode_changed.connect (() => {

                set_modality ((Modality) view_selector.selected);

            });

            // Auto-update settings when changed
            Slingshot.settings.changed.connect (read_settings);

        }

        private bool draw_background (Context cr) {

            Allocation size;
            get_allocation (out size);
            
            // Some (configurable?) values
            double radius = 6.0;
            double offset = 2.0;

            cr.set_antialias (Antialias.SUBPIXEL);

            cr.move_to (0 + radius, 15 + offset);
            // Create the little rounded triangle
            cr.line_to (20.0, 15.0 + offset);
            //cr.line_to (30.0, 0.0 + offset);
            cr.arc (35.0, 0.0 + offset + radius, radius - 1.0, -2.0 * Math.PI / 2.7, -7.0 * Math.PI / 3.2);
            cr.line_to (50.0, 15.0 + offset);
            // Create the rounded square
            cr.arc (0 + size.width - radius - offset, 15.0 + radius + offset, 
                         radius, Math.PI * 1.5, Math.PI * 2);
            cr.arc (0 + size.width - radius - offset, 0 + size.height - radius - offset, 
                         radius, 0, Math.PI * 0.5);
            cr.arc (0 + radius + offset, 0 + size.height - radius - offset, 
                         radius, Math.PI * 0.5, Math.PI);
            cr.arc (0 + radius + offset, 15 + radius + offset, radius, Math.PI, Math.PI * 1.5);

            pick_background_color (cr);

            cr.fill_preserve ();

            // Paint a little white border
            cr.set_source_rgba (1.0, 1.0, 1.0, 1.0);
            cr.set_line_width (0.5);
            cr.stroke ();

            return false;

        }

        public bool draw_pages_background (Widget widget, Context cr) {

            Allocation size;
            widget.get_allocation (out size);

            cr.rectangle (0, 0, size.width, size.height);

            pick_background_color (cr);

            cr.fill_preserve ();

            return false;

        }

        private void pick_background_color (Context cr) {

            switch (bg_color) {
                case BackgroundColor.BLACK:
                    cr.set_source_rgba (0.1, 0.1, 0.1, 0.9);
                    break;
                case BackgroundColor.GREY:
                    cr.set_source_rgba (0.3, 0.3, 0.3, 0.9);
                    break;
                case BackgroundColor.RED:
                    cr.set_source_rgba (0.2, 0.1, 0.1, 0.9);
                    break;
                case BackgroundColor.BLUE:
                    cr.set_source_rgba (0.1, 0.1, 0.2, 0.9);
                    break;
                case BackgroundColor.GREEN:
                    cr.set_source_rgba (0.1, 0.2, 0.1, 0.9);
                    break;
                case BackgroundColor.ORANGE:
                    cr.set_source_rgba (0.4, 0.2, 0.1, 0.9);
                    break;
                case BackgroundColor.GOLD:
                    cr.set_source_rgba (0.5, 0.4, 0.0, 0.9);
                    break;
                case BackgroundColor.VIOLET:
                    cr.set_source_rgba (0.2, 0.1, 0.2, 0.9);
                    break;
            }

        }

        public override bool key_press_event (Gdk.EventKey event) {

            switch (Gdk.keyval_name (event.keyval)) {

                case "Escape":
                    hide_slingshot ();
                    return true;

                case "Return":
                    if (modality == Modality.SEARCH_VIEW) {
                        search_view.launch_first ();
                        hide_slingshot ();
                    }
                    return true;

                case "Alt":
                    message ("Alt pressed");
                    break;

                case "1":
                case "KP_1":
                    page_switcher.set_active (0);
                    break;

                case "2":
                case "KP_2":
                    page_switcher.set_active (1);
                    break;

                case "3":
                case "KP_3":
                    page_switcher.set_active (2);
                    break;

                case "4":
                case "KP_4":
                    page_switcher.set_active (3);
                    break;

                case "5":
                case "KP_5":
                    page_switcher.set_active (4);
                    break;

                case "6":
                case "KP_6":
                    page_switcher.set_active (5);
                    break;

                case "7":
                case "KP_7":
                    page_switcher.set_active (6);
                    break;

                case "8":
                case "KP_8":
                    page_switcher.set_active (7);
                    break;

                case "9":
                case "KP_9":
                    page_switcher.set_active (8);
                    break;

                case "0":
                case "KP_0":
                    page_switcher.set_active (9);
                    break;

                case "Down":
                    break;

                default:
                    if (!searchbar.has_focus)
                        searchbar.grab_focus ();
                    break;

            }

            base.key_press_event (event);
            return false;

        }

        public override bool scroll_event (EventScroll event) {

            switch (event.direction.to_string ()) {
                case "GDK_SCROLL_UP":
                case "GDK_SCROLL_LEFT":
                    if (modality == Modality.NORMAL_VIEW)
                        page_switcher.set_active (page_switcher.active - 1);
                    else if (modality == Modality.SEARCH_VIEW)
                        search_view_up ();
                    break;
                case "GDK_SCROLL_DOWN":
                case "GDK_SCROLL_RIGHT":
                    if (modality == Modality.NORMAL_VIEW)
                        page_switcher.set_active (page_switcher.active + 1);
                    else if (modality == Modality.SEARCH_VIEW)
                        search_view_down ();
                    break;

            }

            return false;

        }

        public void hide_slingshot () {
            
            // Show the first page
            searchbar.text = "";

            hide ();

            grab_remove ((Widget) this);
			get_current_event_device ().ungrab (Gdk.CURRENT_TIME);

        }

        public void show_slingshot () {

            set_modality (Modality.NORMAL_VIEW);

            show_all ();
            searchbar.grab_focus ();
            //Utils.present_window (this);

        }

        private void page_left (int step = 1) {

            // Avoid unexpected behavior
            if (modality != Modality.NORMAL_VIEW)
                return;

            if (current_position < 0) {
                int count = 0;
                int val = columns*130*step / 10;
                Timeout.add (20 / step, () => {

                    if (count >= columns*130*step) {
                        count = 0;
                        return false;
                    }
                    pages.move (grid, current_position + val, 0);
                    current_position += val;
                    count += val;
                    return true;

                });
            }

        }

        private void page_right (int step = 1) {

            // Avoid unexpected behavior
            if (modality != Modality.NORMAL_VIEW)
                return;            

            if ((- current_position) < (grid.n_columns*130)) {
                int count = 0;
                int val = columns*130*step / 10;
                Timeout.add (20 / step, () => {

                    if (count >= columns*130*step) {
                        count = 0;
                        return false;
                    }
                    pages.move (grid, current_position - val, 0);
                    current_position -= val;
                    count += val;
                    return true;
                    
                });
            }

        }

        private void search_view_down () {

            if (search_view.apps_showed < 7)
                return;

            if ((search_view_position) > -(search_view.apps_showed*48)) {
                pages.move (search_view, 0, search_view_position - 2*48);
                search_view_position -= 2*48;
            }

        }

        private void search_view_up () {

            if (search_view_position < 0) {
                pages.move (search_view, 0, search_view_position + 2*48);
                search_view_position += 2*48;
            }

        }

        private void set_modality (Modality new_modality) {

            modality = new_modality;

            switch (modality) {
                case Modality.NORMAL_VIEW:
                    pages.move (search_view, -130*columns, 0);
                    pages.move (category_view, 130*columns, 0);
                    bottom.show_all ();
                    view_selector.show_all ();
                    view_selector.selected = 0;
                    pages.move (grid, 0, 0);
                    current_position = 0;
                    page_switcher.set_active (0);
                    return;

                case Modality.CATEGORY_VIEW:
                    view_selector.show_all ();
                    view_selector.selected = 1;
                    bottom.hide ();
                    pages.move (grid, columns*130, 0);
                    pages.move (search_view, -columns*130, 0);
                    pages.move (category_view, 0, 0);
                    return;

                case Modality.SEARCH_VIEW:
                    view_selector.hide ();
                    bottom.hide (); // Hide the switcher
                    pages.move (grid, columns*130, 0); // Move the grid away
                    pages.move (category_view, columns*130, 0);
                    pages.move (search_view, 0, 0); // Show the searchview
                    return;
            
            }

        }

        private void search () {

            //Idle.add_full (Priority.HIGH_IDLE, get_apps_by_category.callback);
            //yield;

            var text = searchbar.text.down ().strip ();

            if (text == "") {
                set_modality ((Modality) view_selector.selected);
                return;
            }
            
            if (modality != Modality.SEARCH_VIEW)
                set_modality (Modality.SEARCH_VIEW);
            search_view_position = 0;
            search_view.hide_all ();
            filtered.clear ();

            // There should be a real search engine, which can sort application
            foreach (ArrayList<App> entries in apps.values) {
                foreach (App app in entries) {
                    
                    if (text in app.name.down () ||
                        text in app.exec.down () ||
                        text in app.description.down ())
                        filtered.add (app);
                    else
                        filtered.remove (app);

                }
            }

            if (filtered.size > 20) {
                foreach (App app in filtered[0:20])
                    search_view.show_app (app);
            } else {
                foreach (App app in filtered)
                    search_view.show_app (app);
            }

            if (filtered.size != 1)
                search_view.add_command (text);

        }

        public void populate_grid () {

            page_switcher.clear_children ();
            grid.clear ();

            pages.move (grid, 0, 0);

            page_switcher.append ("1");
            page_switcher.set_active (0);

            foreach (App app in app_system.get_apps_by_name ()) {

                var app_entry = new AppEntry (app);
                
                app_entry.app_launched.connect (hide_slingshot);

                grid.append (app_entry);

                app_entry.show_all ();

            }

            current_position = 0;

        }

        private void read_settings () {

            default_width = Slingshot.settings.width;
            default_height = Slingshot.settings.height;

            bg_color = Slingshot.settings.background_color;
            this.queue_draw ();
            if (pages != null)
                pages.queue_draw ();

        }

    }

}
