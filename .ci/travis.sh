#!/bin/bash
# Attention, there is no "-x" to avoid problems on Travis
set -e

case $1 in

init-m2-settings)
  MVN_SETTINGS=${TRAVIS_HOME}/.m2/settings.xml
  export JAVA_HOME="/usr/lib/jvm/"$(ls /usr/lib/jvm/ | head -n 1)"/"
  echo "JAVA_HOME="$JAVA_HOME
  export PATH=$JAVA_HOME/bin:$PATH
  if [[ -f ${MVN_SETTINGS} ]]; then
    if [[ $TRAVIS_OS_NAME == 'osx' ]]; then
      sed -i'' -e "/<mirrors>/,/<\/mirrors>/ d" $MVN_SETTINGS
    else
      xmlstarlet ed --inplace -d "//mirrors" $MVN_SETTINGS
    fi
  fi
  ;;

init-m2-repo)
  if [[ $USE_MAVEN_REPO == 'true' && ! -d "~/.m2" ]]; then
   echo "Maven local repo cache is not found, initializing it ..."
   cd sevntu-checks
   mvn  -e --no-transfer-progress install -Pno-validations
   cd ../
  fi
  ;;

pr-description)
  .ci/xtr_pr-description.sh
  ;;

eclipse-cs)
  cd eclipsecs-sevntu-plugin
  # we can not use here 'exec-maven-plugin' as requies all dependencies resolved
  ECLIPSECS_TAG_NAME=$(grep "eclipsecs.version" pom.xml \
                           | head -n 1 \
                           | sed -E "s/<(\w|\.|\/)*>//g" \
                           | tr -d '[:space:]' \
                           | sed "s/-SNAPSHOT//")
  cd ../
  cd sevntu-checks
  mvn -B -e clean install -Dmaven.test.skip=true -Pno-validations
  cd ..
  mkdir -p .ci-temp
  cd .ci-temp
  git clone https://github.com/checkstyle/eclipse-cs.git
  cd eclipse-cs/
  echo "Eclipse-cs tag: "$ECLIPSECS_TAG_NAME
  git checkout $ECLIPSECS_TAG_NAME
  mvn -B -e install
  cd ../../
  cd eclipsecs-sevntu-plugin
  mvn -e verify
  mvn -e javadoc:javadoc
  ;;

idea-extension)
  cd sevntu-checks
  mvn -e clean install -Dmaven.test.skip=true -Pno-validations
  cd ..
  cd sevntu-checkstyle-idea-extension
  mvn -e verify
  mvn -e javadoc:javadoc
  ;;

sonar-plugin)
  cd sevntu-checks
  mvn -e clean install -Dmaven.test.skip=true -Pno-validations
  cd ..
  cd sevntu-checkstyle-sonar-plugin
  mvn -e verify
  mvn -e javadoc:javadoc
  ;;

sevntu-checks)
  cd sevntu-checks
  mvn -e -Pcoverall install
  mvn -e verify -Pno-validations,selftesting
  mvn -e javadoc:javadoc
  if [[ $TRAVIS == 'true' ]]; then
   mvn -e -Pcoverall jacoco:report coveralls:report
  fi
  ;;

all-sevntu-checks-contribution)
  mkdir -p .ci-temp
  wget -q \
    https://raw.githubusercontent.com/checkstyle/contribution/master/checkstyle-tester/checks-sevntu-error.xml
  xmlstarlet sel --net --template -m .//module -v "@name" -n checks-sevntu-error.xml \
    | grep -vE "Checker|TreeWalker|Filter|Holder" | grep -v "^$" \
    | sed "s/com\.github\.sevntu\.checkstyle\.checks\..*\.//" \
    | sort | uniq | sed "s/Check$//" > .ci-temp/web.txt
  xmlstarlet sel --net --template -m .//module -v "@name" -n sevntu-checks/sevntu-checks.xml \
    | grep -vE "Checker|TreeWalker|Filter|Holder" | grep -v "^$" \
    | sed "s/com\.github\.sevntu\.checkstyle\.checks\..*\.//" \
    | sort | uniq | sed "s/Check$//" > .ci-temp/file.txt
  diff -u .ci-temp/web.txt .ci-temp/file.txt
  ;;

checkstyle-regression)
  mkdir -p .ci-temp
  cd .ci-temp
  git clone https://github.com/checkstyle/checkstyle
  cd ../
  # update checkstyle_sevntu_checks.xml file in checkstyle for new modules
  cd sevntu-checks
  SEVNTU_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' \
                   --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo sevntu version:$SEVNTU_VERSION
  ECLIPSE_CS_VERSION=$(mvn -e -q -Dexec.executable='echo' \
                   -Dexec.args='${checkstyle.eclipse-cs.version}' \
                   --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo eclipse-cs version:$ECLIPSE_CS_VERSION
  mvn -e install -Pno-validations
  mvn -e test -Dtest=CheckstyleRegressionTest#setupFiles -Dregression-path=../.ci-temp
  cd ../
  # execute checkstyle validation on updated config file
  cd .ci-temp/checkstyle
  mvn -e clean verify -e -DskipTests -DskipITs -Dpmd.skip=true \
      -Dfindbugs.skip=true -Dcobertura.skip=true -Dxml.skip=true \
      -Dmaven.sevntu-checkstyle-check.checkstyle.version=$ECLIPSE_CS_VERSION \
      -Dmaven.sevntu.checkstyle.plugin.version=$SEVNTU_VERSION
  ;;

eclipse-analysis)
  cd sevntu-checks
  mvn -e clean compile exec:exec -Peclipse-compiler
  ;;

sonarqube)
  # token could be generated at https://sonarcloud.io/account/security/
  # executon on local: SONAR_TOKEN=xxxxxxxxxx ./.ci/travis.sh sonarqube
  if [[ -v TRAVIS_PULL_REQUEST && $TRAVIS_PULL_REQUEST && $TRAVIS_PULL_REQUEST =~ ^([0-9]*)$ ]];
    then
      exit 0;
  fi
  if [[ -z $SONAR_TOKEN ]]; then echo "SONAR_TOKEN is not set"; sleep 5s; exit 1; fi
  export MAVEN_OPTS='-Xmx2000m'
  cd sevntu-checks
  mvn -e clean package sonar:sonar \
       -Dsonar.organization=checkstyle \
       -Dsonar.host.url=https://sonarcloud.io \
       -Dsonar.login=$SONAR_TOKEN \
       -Dmaven.test.failure.ignore=true \
       -Dcheckstyle.skip=true -Dpmd.skip=true
  ;;

*)
  echo "Unexpected argument: $1"
  sleep 5s
  false
  ;;

esac
