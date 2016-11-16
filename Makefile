# use JDK1.5 to build native libraries

include Makefile.common

RESOURCE_DIR = src/main/resources

.phony: all package win32 mac32 mac64 linux32 native deploy
.phony: mac64

all: package

deploy: 
	mvn deploy 

MVN:=mvn
SRC:=src/main/java
SQLITE_OUT:=$(TARGET)/$(sqlite)-$(OS_NAME)-$(OS_ARCH)
#SQLITE_ARCHIVE:=$(TARGET)/$(sqlite)-amal.zip
#SQLITE_UNPACKED:=$(TARGET)/sqlite-unpack.log
#SQLITE_AMAL_DIR=$(TARGET)/$(SQLITE_AMAL_PREFIX)
SQLCIPHER_DIR:=sqlcipher

# Note that that SQLITE_OMIT_LOAD_EXTENSION cannot be disabled on Macs due
# to a bug in the SQLITE automake config. To make matters worse, SQLITE
# doesn't even include the function to test whether extensions can be 
# loaded unless SQLITE_OMIT_LOAD_EXTENSION = 0. Rather than try to patch
# SQLITE, we just include that flag here to be explicit, AND so that compiling
# the JNI code will function correctly and not try to test if extensions 
# are available.
SQLITE_FLAGS:=\
	-DSQLITE_OMIT_LOAD_EXTENSION \
	-DSQLITE_ENABLE_UPDATE_DELETE_LIMIT \
	-DSQLITE_ENABLE_COLUMN_METADATA \
	-DSQLITE_CORE \
	-DSQLITE_ENABLE_FTS3 \
	-DSQLITE_ENABLE_FTS3_PARENTHESIS \
	-DSQLITE_ENABLE_RTREE \
	-DSQLITE_ENABLE_STAT2 \
	-DSQLITE_HAS_CODEC \
	-fPIC

	
CFLAGS:= -I$(SQLITE_OUT) $(CFLAGS) $(SQLITE_FLAGS)

$(SQLITE_ARCHIVE):
	@mkdir -p $(@D)
	curl -o$@ http://www.sqlite.org/2013/$(SQLITE_AMAL_PREFIX).zip

$(SQLITE_UNPACKED): $(SQLITE_ARCHIVE)
	unzip -qo $< -d $(TARGET)
	touch $@
	    
$(SQLITE_OUT)/org/sqlite/%.class: src/main/java/org/sqlite/%.java
	@mkdir -p $(@D)
	$(JAVAC) -sourcepath $(SRC) -d $(SQLITE_OUT) $<

jni-header: $(SRC)/org/sqlite/core/NativeDB.h

$(SQLITE_OUT)/NativeDB.h: $(SQLITE_OUT)/org/sqlite/core/NativeDB.class
	$(JAVAH) -classpath $(SQLITE_OUT) -jni -o $@ org.sqlite.core.NativeDB
# Apple uses different include path conventions.
ifeq ($(OS_NAME),Mac)
	cp $@ $@.tmp
	perl -p -e "s/#include \<jni\.h\>/#include \<JavaVM\/jni.h\>/" $@.tmp > $@
	rm $@.tmp
endif


test:
	mvn test


clean: clean-native clean-java clean-tests


$(SQLITE_OUT)/sqlite3.o:
	cd $(SQLCIPHER_DIR); CPPFLAGS="$(SQLITE_FLAGS)" ./configure;
	make -C $(SQLCIPHER_DIR)
	@mkdir -p $(@D)
	cp $(SQLCIPHER_DIR)/sqlite3.o $@
	
#$(SQLITE_OUT)/sqlite3.o : $(SQLITE_AMAL)
#	@mkdir -p $(@D)
#	perl -p -e "s/sqlite3_api;/sqlite3_api = 0;/g" \
#	    $(SQLITE_AMAL_DIR)/sqlite3ext.h > $(SQLITE_OUT)/sqlite3ext.h
# insert a code for loading extension functions
#	perl -p -e "s/^opendb_out:/  if(!db->mallocFailed && rc==SQLITE_OK){ rc = RegisterExtensionFunctions(db); }\nopendb_out:/;" \
#	    $(SQLITE_AMAL_DIR)/sqlite3.c > $(SQLITE_OUT)/sqlite3.c
#	cat src/main/ext/*.c >> $(SQLITE_OUT)/sqlite3.c
#	$(CC) -o $@ -c $(CFLAGS) \
#	    -DSQLITE_ENABLE_LOAD_EXTENSION=1 \
#	    -DSQLITE_ENABLE_UPDATE_DELETE_LIMIT \
#	    -DSQLITE_ENABLE_COLUMN_METADATA \
#	    -DSQLITE_CORE \
#	    -DSQLITE_ENABLE_FTS3 \
#	    -DSQLITE_ENABLE_FTS3_PARENTHESIS \
#	    -DSQLITE_ENABLE_RTREE \
#	    -DSQLITE_ENABLE_STAT2 \
#	    -DSQLITE_HAS_CODEC \
#	    $(SQLITE_FLAGS) \
#	    $(SQLITE_OUT)/sqlite3.c

$(SQLITE_OUT)/$(LIBNAME): $(SQLITE_OUT)/sqlite3.o $(SRC)/org/sqlite/core/NativeDB.c $(SQLITE_OUT)/NativeDB.h
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -c -o $(SQLITE_OUT)/NativeDB.o $(SRC)/org/sqlite/core/NativeDB.c
	$(CC) $(CFLAGS) -o $@ $(SQLITE_OUT)/*.o $(LINKFLAGS)
	$(STRIP) $@


NATIVE_DIR=src/main/resources/org/sqlite/native/$(OS_NAME)/$(OS_ARCH)
NATIVE_TARGET_DIR:=$(TARGET)/classes/org/sqlite/native/$(OS_NAME)/$(OS_ARCH)
NATIVE_DLL:=$(NATIVE_DIR)/$(LIBNAME)

native: $(SQLITE_OUT)/sqlite3.o $(NATIVE_DLL)

$(NATIVE_DLL): $(SQLITE_OUT)/$(LIBNAME)
	@mkdir -p $(@D)
	cp $< $@
	@mkdir -p $(NATIVE_TARGET_DIR)
	cp $< $(NATIVE_TARGET_DIR)/$(LIBNAME)


win32: 
	$(MAKE) native CC=i686-w64-mingw32-gcc OS_NAME=Windows OS_ARCH=x86

linux32:
	$(MAKE) native OS_NAME=Linux OS_ARCH=i386

linux64:
	$(MAKE) native OS_NAME=Linux OS_ARCH=x86_64

sparcv9:
	$(MAKE) native OS_NAME=SunOS OS_ARCH=sparcv9

mac32:
	$(MAKE) native OS_NAME=Mac OS_ARCH=i386

mac64:
	$(MAKE) native OS_NAME=Mac OS_ARCH=x86_64


package: $(NATIVE64_DLL) native
	rm -rf target/dependency-maven-plugin-markers
	$(MVN) package

clean-native:
	rm -rf $(TARGET)/$(sqlite)-$(OS_NAME)*

clean-java:
	rm -rf $(TARGET)/*classes
	rm -rf $(TARGET)/sqlite-jdbc-*jar

clean-tests:
	rm -rf $(TARGET)/{surefire*,testdb.jar*}
