/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public errordomain GPhotoError {
    LIBRARY
}

namespace GPhoto {
    // ContextWrapper assigns signals to the various GPhoto.Context callbacks, as well as spins
    // the event loop at opportune times.
    public class ContextWrapper {
        public Context context = new Context();
        
        public ContextWrapper() {
            context.set_idle_func(on_idle);
            context.set_error_func(on_error);
            context.set_status_func(on_status);
            context.set_message_func(on_message);
            context.set_progress_funcs(on_progress_start, on_progress_update, on_progress_stop);
        }
        
        public virtual void idle() {
        }
        
        public virtual void error(string format, void *va_list) {
        }
        
        public virtual void status(string format, void *va_list) {
        }
        
        public virtual void message(string format, void *va_list) {
        }
        
        public virtual void progress_start(float target, string format, void *va_list) {
        }
        
        public virtual void progress_update(float current) {
        }
        
        public virtual void progress_stop() {
        }
        
        private void on_idle(Context context) {
            idle();
            spin_event_loop();
        }

        private void on_error(Context context, string format, void *va_list) {
            error(format, va_list);
        }
        
        private void on_status(Context context, string format, void *va_list) {
            status(format, va_list);
        }
        
        private void on_message(Context context, string format, void *va_list) {
            message(format, va_list);
        }
        
        private uint on_progress_start(Context context, float target, string format, void *va_list) {
            progress_start(target, format, va_list);
            
            return 0;
        }
        
        private void on_progress_update(Context context, uint id, float current) {
            progress_update(current);
            spin_event_loop();
        }
        
        private void on_progress_stop(Context context, uint id) {
            progress_stop();
        }
    }
    
    public void get_info(Context context, Camera camera, string folder, string filename,
        out CameraFileInfo info) throws Error {
        Result res = camera.get_file_info(folder, filename, out info, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file information for %s/%s: %s",
                (int) res, folder, filename, res.as_string());
    }
    
    public Gdk.Pixbuf? load_preview(Context context, Camera camera, string folder, string filename)
        throws Error {
        InputStream ins = load_file_into_stream(context, camera, folder, filename, GPhoto.CameraFileType.PREVIEW);
        if (ins == null)
            return null;
        
        return new Gdk.Pixbuf.from_stream(ins, null);
    }
    
    public Gdk.Pixbuf? load_image(Context context, Camera camera, string folder, string filename) 
        throws Error {
        InputStream ins = load_file_into_stream(context, camera, folder, filename, GPhoto.CameraFileType.NORMAL);
        if (ins == null)
            return null;
        
        return new Gdk.Pixbuf.from_stream(ins, null);
    }

    public void save_image(Context context, Camera camera, string folder, string filename, 
        File dest_file) throws Error {
        GPhoto.CameraFile camera_file;
        GPhoto.Result res = GPhoto.CameraFile.create(out camera_file);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error allocating camera file: %s", (int) res, res.as_string());
        
        res = camera.get_file(folder, filename, GPhoto.CameraFileType.NORMAL, camera_file, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file object for %s/%s: %s", 
                (int) res, folder, filename, res.as_string());

        res = camera_file.save(dest_file.get_path());
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error copying file %s/%s to %s: %s", (int) res, 
                folder, filename, dest_file.get_path(), res.as_string());
    }
    
    public Exif.Data? load_exif(Context context, Camera camera, string folder, string filename)
        throws Error {
        uint8[] buffer = load_file_into_buffer(context, camera, folder, filename, GPhoto.CameraFileType.EXIF);
        if (buffer == null)
            return null;
        
        Exif.Data data = Exif.Data.new_from_data(buffer, buffer.length);
        data.fix();
        
        return data;
    }
    
    // Returns an InputStream for the requested camera file.  The stream should be used
    // immediately rather than stored, as the backing is temporary in nature.
    public InputStream load_file_into_stream(Context context, Camera camera, string folder, string filename, 
        GPhoto.CameraFileType filetype) throws Error {
        GPhoto.CameraFile camera_file;
        GPhoto.Result res = GPhoto.CameraFile.create(out camera_file);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error allocating camera file: %s", (int) res, res.as_string());
        
        res = camera.get_file(folder, filename, filetype, camera_file, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file object for %s/%s: %s", 
                (int) res, folder, filename, res.as_string());
        
        // if entire file fits in memory, return a stream from that ... can't merely wrap
        // MemoryInputStream around the camera_file buffer, as that will be destroyed when the
        // function returns
        unowned uint8[] data;
        res = camera_file.get_data_and_size(out data);
        if (res == Result.OK) {
            uint8 *buffer = malloc(data.length);
            Memory.copy(buffer, data, data.length);
            
            return new MemoryInputStream.from_data(buffer, data.length, on_mins_destroyed);
        }

        // if not stored in memory, try copying it to a temp file and then reading out of that
        File temp = AppWindow.get_temp_dir().get_child("import.tmp");
        res = camera_file.save(temp.get_path());
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error copying file %s/%s to %s: %s", (int) res, 
                folder, filename, temp.get_path(), res.as_string());
        
        return temp.read(null);
    }
    
    private static void on_mins_destroyed(void *data) {
        free(data);
    }
    
    // Returns a buffer with the requested file, if within reason.  Use load_file for larger files.
    public uint8[]? load_file_into_buffer(Context context, Camera camera, string folder,
        string filename, CameraFileType filetype) throws Error {
        GPhoto.CameraFile camera_file;
        GPhoto.Result res = GPhoto.CameraFile.create(out camera_file);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error allocating camera file: %s", (int) res, res.as_string());
        
        res = camera.get_file(folder, filename, filetype, camera_file, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file object for %s/%s: %s", 
                (int) res, folder, filename, res.as_string());
        
        // if buffer can be loaded into memory, return a copy of that (can't return buffer itself
        // as it will be destroyed when the camera_file is unref'd)
        unowned uint8[] data;
        res = camera_file.get_data_and_size(out data);
        if (res != Result.OK)
            return null;
        
        uint8[] buffer = new uint8[data.length];
        Memory.copy(buffer, data, buffer.length);
        
        return buffer;
    }
}

