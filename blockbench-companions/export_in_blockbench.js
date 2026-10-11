(async function(character) {
    const fs = require('fs');
    const folder = 'D:/chase/code/gymni-codered/blockbench-companions/' + character + '/';
    const path = folder + character + '.bbmodel';
    Codecs.project.load(JSON.parse(fs.readFileSync(path, 'utf8')), {path});
    await Promise.all(Texture.all.map(texture => texture.img.complete && texture.img.naturalWidth ? Promise.resolve() : new Promise(resolve => texture.img.addEventListener('load', resolve, {once:true}))));
    const view = Preview.all.find(p => p.id === 'mcp_offscreen_companion_review');
    if (!view) throw new Error('Create the companion_review offscreen view first');
    const box = new THREE.Box3();
    Mesh.all.forEach(m => Object.values(m.vertices).forEach(v => box.expandByPoint(new THREE.Vector3().fromArray(v))));
    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());
    const distance = Math.max(size.x, size.y) * 1.7;
    view.camera.position.copy(center).add(new THREE.Vector3(.24, .18, 1).normalize().multiplyScalar(distance));
    view.controls.target.copy(center);
    view.controls.update();
    BarItems.view_mode.set('material');
    BarItems.view_mode.onChange();
    Canvas.updateAllBones();
    Canvas.updateAllPositions();
    Canvas.updateAllFaces();
    const room = new THREE.Scene();
    room.background = new THREE.Color(.16, .18, .20);
    for (const [position, scale, strength] of [
        [[-3, 3, 3], [2, 3, .1], 3], [[3, 1, 2], [1, 3, .1], 1.5], [[0, 4, -2], [3, .1, 2], 2.5]
    ]) {
        const panel = new THREE.Mesh(new THREE.BoxGeometry(...scale), new THREE.MeshBasicMaterial({color:new THREE.Color(strength, strength, strength)}));
        panel.position.fromArray(position);
        room.add(panel);
    }
    const pmrem = new THREE.PMREMGenerator(view.renderer);
    const environment = pmrem.fromScene(room, .05, .1, 100);
    TextureGroup.all.forEach(group => {
        group.material.envMap = environment.texture;
        group.material.envMapIntensity = 1;
        group.material.needsUpdate = true;
    });
    Modes.options.animate.select();
    const captureScene = new THREE.Scene();
    captureScene.add(new THREE.AmbientLight(0xffffff, .45));
    for (const [position, strength] of [[[-3,4,5],1.5],[[3,2,2],.5]]) {
        const light = new THREE.DirectionalLight(0xffffff,strength);
        light.position.fromArray(position);
        captureScene.add(light);
    }
    const colorMap = new THREE.Texture(Texture.all[0].img);
    colorMap.colorSpace = THREE.SRGBColorSpace;
    colorMap.encoding = THREE.sRGBEncoding;
    colorMap.needsUpdate = true;
    const captureMaterial = new THREE.MeshStandardMaterial({map:colorMap,metalness:0,roughness:{atlas:.83,flex:.54,pip:.32}[character],envMap:environment.texture,envMapIntensity:.8,side:THREE.DoubleSide});
    const captureMeshes = Mesh.all.map(model => {
        const mesh = new THREE.Mesh(model.mesh.geometry, captureMaterial);
        mesh.matrixAutoUpdate = false;
        captureScene.add(mesh);
        return [model,mesh];
    });
    const capture = async file => {
        Project.model_3d.updateMatrixWorld(true);
        captureMeshes.forEach(([model,mesh]) => mesh.matrix.copy(model.mesh.matrixWorld));
        view.renderer.render(captureScene,view.camera);
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = 640;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(view.canvas,0,0);
        const rgba = ctx.getImageData(0,0,640,640).data;
        if (!rgba.some((v,i) => i%4===3 && v>0)) throw new Error('Blank screenshot: '+file);
        fs.writeFileSync(file,Buffer.from(canvas.toDataURL().split(',')[1],'base64'));
    };
    Animator.showDefaultPose();
    await capture(folder + 'neutral.png');
    const previewFolder = folder + 'review/';
    fs.mkdirSync(previewFolder, {recursive:true});
    const checks = [];
    for (const animation of Animation.all) {
        Animation.all.forEach(a => a.playing = false);
        animation.select();
        animation.playing = true;
        const frameData = [];
        for (const fraction of [0, .25, .5, .75, 1]) {
            Timeline.setTime(animation.length * fraction);
            Animator.preview();
            const values = Mesh.all.flatMap(m => Array.from(m.mesh.geometry.attributes.position.array));
            if (!values.every(Number.isFinite)) throw new Error('Nonfinite geometry in ' + animation.name);
            frameData.push(values);
            if (fraction > 0 && fraction < 1) await capture(previewFolder + animation.name + '-' + fraction + '.png');
        }
        const seam = frameData[0].reduce((max,v,i) => Math.max(max,Math.abs(v-frameData[4][i])),0);
        const motion = frameData[0].reduce((max,v,i) => Math.max(max,Math.abs(v-frameData[1][i])),0);
        if (seam > .01 || motion < .00001) throw new Error('Animation check failed: ' + animation.name);
        checks.push({name:animation.name, seam, motion});
    }
    for (const name of ['float', 'coaching', 'celebrate', 'stretch']) {
        const animation = Animation.all.find(a => a.name === name);
        Animation.all.forEach(a => a.playing = false);
        animation.select();
        animation.playing = true;
        const frames = previewFolder + name + '/';
        fs.mkdirSync(frames, {recursive:true});
        for (let i=0; i<32; i++) {
            Timeline.setTime(animation.length * i/32);
            Animator.preview();
            await capture(frames + String(i).padStart(3, '0') + '.png');
        }
    }
    Animation.all.forEach(a => a.playing = false);
    Animator.showDefaultPose();
    Modes.options.edit.select();
    TextureGroup.all.forEach(group => {
        group.material.map = colorMap;
        group.material.needsUpdate = true;
    });
    const glb = await Codecs.gltf.compile({encoding:'binary',scale:16,embed_textures:true,animations:true,armature:false,merge_armature:character !== 'atlas'});
    fs.writeFileSync(folder + character + '.glb', Buffer.from(glb));
    fs.writeFileSync(path, Codecs.project.compile({bitmaps:true,absolute_paths:false}));
    fs.writeFileSync(folder + 'blockbench-validation.json', JSON.stringify({version:Blockbench.version,checks,errors:Validator.errors},null,2));
    Project.saved = true;
    const idle = Animation.all.find(a => a.name === 'idle');
    Modes.options.animate.select();
    idle.select();
    idle.playing = true;
    Timeline.setTime(0);
    Animator.preview();
    return {character, project:Project.uuid, triangles:Mesh.all.reduce((sum,m)=>sum+Object.keys(m.faces).length,0), bones:ArmatureBone.all.length, clips:Animation.all.length, bytes:glb.byteLength, checks};
})
